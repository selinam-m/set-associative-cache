#include "cache_model.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

static uint32_t rng_state = 1;

static uint32_t next_rand() {
    rng_state = rng_state * 1103515245u + 12345u;
    return (rng_state >> 16) & 0x7fffffffu;
}

static void seed_rand(uint32_t s) { rng_state = s; }

static std::vector<Access> gen_random(size_t n, uint32_t ws_bytes, uint32_t seed) {
    std::vector<Access> t;
    t.reserve(n);
    seed_rand(seed);
    for (size_t i = 0; i < n; i++) {
        Access a;
        a.addr = (next_rand() % ws_bytes) & ~3u;
        a.data = next_rand();
        a.is_write = (next_rand() & 1) != 0;
        t.push_back(a);
    }
    return t;
}

static std::vector<Access> gen_stream(size_t n, uint32_t stride, uint32_t limit) {
    std::vector<Access> t;
    t.reserve(n);
    uint32_t addr = 0;
    seed_rand(7);
    for (size_t i = 0; i < n; i++) {
        Access a;
        a.addr = addr & ~3u;
        a.data = next_rand();
        a.is_write = (i % 4) == 3;
        t.push_back(a);
        addr += stride;
        if (addr >= limit) addr = 0;
    }
    return t;
}

static void matmul_body(std::vector<Access> &t, int i, int j, int k, int dim,
                        uint32_t a_base, uint32_t b_base, uint32_t c_base) {
    Access a;
    a.data = 0;
    a.is_write = false;
    a.addr = a_base + 4 * (i * dim + k);
    t.push_back(a);
    a.addr = b_base + 4 * (k * dim + j);
    t.push_back(a);
    a.addr = c_base + 4 * (i * dim + j);
    t.push_back(a);
    a.is_write = true;
    t.push_back(a);
}

static std::vector<Access> gen_matmul(int dim) {
    std::vector<Access> t;
    uint32_t sz = (uint32_t)(dim * dim * 4);
    for (int i = 0; i < dim; i++)
        for (int j = 0; j < dim; j++)
            for (int k = 0; k < dim; k++)
                matmul_body(t, i, j, k, dim, 0, sz, 2 * sz);
    return t;
}

static std::vector<Access> gen_matmul_blocked(int dim, int block) {
    std::vector<Access> t;
    uint32_t sz = (uint32_t)(dim * dim * 4);
    for (int ii = 0; ii < dim; ii += block)
        for (int jj = 0; jj < dim; jj += block)
            for (int kk = 0; kk < dim; kk += block)
                for (int i = ii; i < ii + block && i < dim; i++)
                    for (int j = jj; j < jj + block && j < dim; j++)
                        for (int k = kk; k < kk + block && k < dim; k++)
                            matmul_body(t, i, j, k, dim, 0, sz, 2 * sz);
    return t;
}

static CacheConfig make_config(int sets, int ways, bool wb) {
    CacheConfig c;
    c.num_sets = sets;
    c.num_ways = ways;
    c.line_words = 4;
    c.write_back = wb;
    c.write_allocate = wb;
    return c;
}

static void run_row(const char *label, const CacheConfig &cfg,
                    const std::vector<Access> &trace) {
    CacheModel m(cfg);
    m.run(trace);
    const CacheStats &s = m.stats();
    printf("  %-22s %4d x %-2d  %5d B   %6.2f%%   %6.2f%%   %8llu  %8llu\n",
           label, cfg.num_sets, cfg.num_ways, m.capacity_bytes(),
           s.load_hit_rate(), s.overall_hit_rate(),
           (unsigned long long)s.mem_reads, (unsigned long long)s.mem_writes);
}

static void header(const char *title, size_t ops) {
    printf("\n%s  (%llu accesses)\n", title, (unsigned long long)ops);
    printf("  %-22s %-12s %-8s %-9s %-9s %-9s %s\n",
           "config", "sets x ways", "size", "load hit", "all hit", "mem rd", "mem wr");
}

static void sweep(const char *title, const std::vector<Access> &trace) {
    header(title, trace.size());
    run_row("direct-mapped 1 KB", make_config(64, 1, true), trace);
    run_row("2-way 2 KB", make_config(64, 2, true), trace);
    run_row("4-way 4 KB", make_config(64, 4, true), trace);
    run_row("4 KB direct-mapped", make_config(256, 1, true), trace);
    run_row("4 KB 2-way", make_config(128, 2, true), trace);
    run_row("4 KB 4-way", make_config(64, 4, true), trace);
    run_row("4 KB 8-way", make_config(32, 8, true), trace);
    run_row("4-way write-through", make_config(64, 4, false), trace);
}

static void emit(const std::string &dir, const std::vector<Access> &trace,
                 const CacheConfig &cfg) {
    CacheModel m(cfg);
    m.run(trace);
    const CacheStats &s = m.stats();

    std::string tp = dir + "/trace.hex";
    std::string ep = dir + "/expected.hex";

    FILE *f = fopen(tp.c_str(), "w");
    if (!f) {
        fprintf(stderr, "cannot write %s\n", tp.c_str());
        exit(1);
    }
    for (size_t i = 0; i < trace.size(); i++)
        fprintf(f, "%x %08x %08x\n", trace[i].is_write ? 1 : 0,
                trace[i].addr, trace[i].data);
    fclose(f);

    f = fopen(ep.c_str(), "w");
    if (!f) {
        fprintf(stderr, "cannot write %s\n", ep.c_str());
        exit(1);
    }
    fprintf(f, "%08x\n", (unsigned)trace.size());
    fprintf(f, "%08x\n", (unsigned)s.load_hits);
    fprintf(f, "%08x\n", (unsigned)s.load_misses);
    fprintf(f, "%08x\n", (unsigned)s.store_hits);
    fprintf(f, "%08x\n", (unsigned)s.store_misses);
    fprintf(f, "%08x\n", (unsigned)s.writebacks);
    fprintf(f, "%08x\n", (unsigned)s.mem_reads);
    fprintf(f, "%08x\n", (unsigned)s.mem_writes);
    fclose(f);

    printf("\nco-verification trace written to %s (%llu accesses)\n",
           tp.c_str(), (unsigned long long)trace.size());
    printf("expected counters: LH=%llu LM=%llu SH=%llu SM=%llu WB=%llu rd=%llu wr=%llu\n",
           (unsigned long long)s.load_hits, (unsigned long long)s.load_misses,
           (unsigned long long)s.store_hits, (unsigned long long)s.store_misses,
           (unsigned long long)s.writebacks, (unsigned long long)s.mem_reads,
           (unsigned long long)s.mem_writes);
}

int main(int argc, char **argv) {
    std::string outdir = ".";
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-o") == 0 && i + 1 < argc) outdir = argv[++i];
    }

    std::vector<Access> small = gen_random(20000, 1024, 12345);
    std::vector<Access> big = gen_random(20000, 65536, 999);
    std::vector<Access> strm = gen_stream(20000, 4, 65536);
    std::vector<Access> mm = gen_matmul(32);
    std::vector<Access> mmb = gen_matmul_blocked(32, 8);

    printf("cache design space exploration\n");
    printf("16-byte lines, LRU replacement, write-back/write-allocate unless noted\n");

    sweep("random, 1 KB working set", small);
    sweep("random, 64 KB working set", big);
    sweep("sequential stream, 64 KB", strm);
    sweep("matrix multiply 32x32, naive", mm);
    sweep("matrix multiply 32x32, 8x8 blocked", mmb);

    std::vector<Access> cov = gen_random(2000, 16384, 4242);
    emit(outdir, cov, make_config(64, 4, true));
    return 0;
}
