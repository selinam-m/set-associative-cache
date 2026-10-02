#ifndef CACHE_MODEL_H
#define CACHE_MODEL_H

#include <cstdint>
#include <vector>

struct CacheConfig {
    int num_sets;
    int num_ways;
    int line_words;
    bool write_back;
    bool write_allocate;
};

struct CacheStats {
    uint64_t load_hits = 0;
    uint64_t load_misses = 0;
    uint64_t store_hits = 0;
    uint64_t store_misses = 0;
    uint64_t writebacks = 0;
    uint64_t mem_reads = 0;
    uint64_t mem_writes = 0;

    uint64_t loads() const { return load_hits + load_misses; }
    uint64_t stores() const { return store_hits + store_misses; }
    double load_hit_rate() const;
    double overall_hit_rate() const;
};

struct Access {
    uint32_t addr;
    uint32_t data;
    bool is_write;
};

class CacheModel {
public:
    explicit CacheModel(const CacheConfig &c);

    void reset();
    void access(uint32_t addr, bool is_write);
    void run(const std::vector<Access> &trace);

    const CacheStats &stats() const { return st; }
    const CacheConfig &config() const { return cfg; }
    int capacity_bytes() const;

private:
    struct Line {
        bool valid;
        bool dirty;
        uint32_t tag;
        int age;
    };

    CacheConfig cfg;
    CacheStats st;
    std::vector<std::vector<Line> > sets;
    int byte_bits;
    int word_bits;
    int index_bits;

    uint32_t index_of(uint32_t addr) const;
    uint32_t tag_of(uint32_t addr) const;
    int find_hit(uint32_t set, uint32_t tag) const;
    int pick_victim(uint32_t set) const;
    void touch(uint32_t set, int way);
};

#endif
