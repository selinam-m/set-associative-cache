#include "cache_model.h"

static int ilog2(int n) {
    int r = 0;
    while ((1 << r) < n) r++;
    return r;
}

double CacheStats::load_hit_rate() const {
    if (loads() == 0) return 0.0;
    return 100.0 * (double)load_hits / (double)loads();
}

double CacheStats::overall_hit_rate() const {
    uint64_t total = loads() + stores();
    if (total == 0) return 0.0;
    return 100.0 * (double)(load_hits + store_hits) / (double)total;
}

CacheModel::CacheModel(const CacheConfig &c) : cfg(c) {
    byte_bits = 2;
    word_bits = ilog2(cfg.line_words);
    index_bits = ilog2(cfg.num_sets);
    sets.resize(cfg.num_sets);
    for (int s = 0; s < cfg.num_sets; s++) sets[s].resize(cfg.num_ways);
    reset();
}

int CacheModel::capacity_bytes() const {
    return cfg.num_sets * cfg.num_ways * cfg.line_words * 4;
}

void CacheModel::reset() {
    st = CacheStats();
    for (int s = 0; s < cfg.num_sets; s++)
        for (int w = 0; w < cfg.num_ways; w++) {
            sets[s][w].valid = false;
            sets[s][w].dirty = false;
            sets[s][w].tag = 0;
            sets[s][w].age = w;
        }
}

uint32_t CacheModel::index_of(uint32_t addr) const {
    return (addr >> (byte_bits + word_bits)) & (uint32_t)(cfg.num_sets - 1);
}

uint32_t CacheModel::tag_of(uint32_t addr) const {
    return addr >> (byte_bits + word_bits + index_bits);
}

int CacheModel::find_hit(uint32_t set, uint32_t tag) const {
    for (int w = 0; w < cfg.num_ways; w++)
        if (sets[set][w].valid && sets[set][w].tag == tag) return w;
    return -1;
}

int CacheModel::pick_victim(uint32_t set) const {
    for (int w = 0; w < cfg.num_ways; w++)
        if (!sets[set][w].valid) return w;
    for (int w = 0; w < cfg.num_ways; w++)
        if (sets[set][w].age == cfg.num_ways - 1) return w;
    return 0;
}

void CacheModel::touch(uint32_t set, int way) {
    int old = sets[set][way].age;
    for (int w = 0; w < cfg.num_ways; w++) {
        if (w == way) sets[set][w].age = 0;
        else if (sets[set][w].age < old) sets[set][w].age++;
    }
}

void CacheModel::access(uint32_t addr, bool is_write) {
    uint32_t set = index_of(addr);
    uint32_t tag = tag_of(addr);
    int way = find_hit(set, tag);

    if (way >= 0) {
        if (is_write) {
            st.store_hits++;
            if (cfg.write_back) sets[set][way].dirty = true;
            else st.mem_writes++;
        } else {
            st.load_hits++;
        }
        touch(set, way);
        return;
    }

    if (is_write) st.store_misses++;
    else st.load_misses++;

    bool allocate = !is_write || cfg.write_allocate;

    if (!allocate) {
        st.mem_writes++;
        return;
    }

    int v = pick_victim(set);
    if (cfg.write_back && sets[set][v].valid && sets[set][v].dirty) {
        st.writebacks++;
        st.mem_writes++;
    }

    st.mem_reads++;
    sets[set][v].valid = true;
    sets[set][v].dirty = false;
    sets[set][v].tag = tag;
    touch(set, v);

    if (is_write) {
        if (cfg.write_back) sets[set][v].dirty = true;
        else st.mem_writes++;
    }
}

void CacheModel::run(const std::vector<Access> &trace) {
    for (size_t i = 0; i < trace.size(); i++)
        access(trace[i].addr, trace[i].is_write);
}
