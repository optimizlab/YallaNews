#include "yalla_core.h"
#include <string>
#include <vector>
#include <unordered_map>
#include <algorithm>
#include <cmath>
#include <sstream>
#include <random>
#include <cstdint>

struct YallaDeduplicator {
    float threshold = 0.85f;
    std::vector<uint64_t> simhashes;  // SimHash for near-duplicate detection
    std::vector<std::string> fingerprints;  // Jaccard fingerprints
    std::vector<std::string> urls;  // Track URLs for exact match

    // SimHash implementation for near-duplicate detection
    uint64_t compute_simhash(const YallaArticle* article) {
        std::string combined;
        if (article->title) combined += article->title;
        combined += " ";
        if (article->content) combined += article->content;

        std::transform(combined.begin(), combined.end(), combined.begin(),
            [](unsigned char c) { return std::tolower(c); });

        // Tokenize into shingles (3-grams)
        std::vector<uint64_t> shingle_hashes;
        for (size_t i = 0; i + 2 < combined.size(); ++i) {
            if (std::isalnum(static_cast<unsigned char>(combined[i])) &&
                std::isalnum(static_cast<unsigned char>(combined[i+1])) &&
                std::isalnum(static_cast<unsigned char>(combined[i+2]))) {
                uint64_t h = 0;
                h = (h * 31) + combined[i];
                h = (h * 31) + combined[i+1];
                h = (h * 31) + combined[i+2];
                shingle_hashes.push_back(h);
            }
        }

        if (shingle_hashes.empty()) return 0;

        // Compute SimHash
        int64_t bits[64] = {0};
        for (uint64_t shingle : shingle_hashes) {
            for (int b = 0; b < 64; ++b) {
                if (shingle & (1ULL << b)) bits[b] += 1;
                else bits[b] -= 1;
            }
        }

        uint64_t simhash = 0;
        for (int b = 0; b < 64; ++b) {
            if (bits[b] > 0) simhash |= (1ULL << b);
        }
        return simhash;
    }

    std::string compute_fingerprint(const YallaArticle* article) {
        std::string combined = (article->title ? article->title : "") + " " + (article->content ? article->content : "");
        std::transform(combined.begin(), combined.end(), combined.begin(),
            [](unsigned char c) { return std::tolower(c); });

        std::istringstream iss(combined);
        std::vector<std::string> words;
        std::string word;
        while (iss >> word) {
            word.erase(std::remove_if(word.begin(), word.end(),
                [](char c) { return std::ispunct(static_cast<unsigned char>(c)); }), word.end());
            if (word.length() >= 3) words.push_back(word);
        }

        std::sort(words.begin(), words.end());
        words.erase(std::unique(words.begin(), words.end()), words.end());

        std::string fp;
        for (size_t i = 0; i < std::min(words.size(), size_t(100)); ++i) {
            if (i > 0) fp += " ";
            fp += words[i];
        }
        return fp;
    }

    int hamming_distance(uint64_t a, uint64_t b) {
        return __builtin_popcountll(a ^ b);
    }

    float jaccard_similarity(const std::string& a, const std::string& b) {
        std::istringstream issa(a), issb(b);
        std::unordered_map<std::string, int> count_a, count_b;
        std::string word;

        while (issa >> word) count_a[word]++;
        while (issb >> word) count_b[word]++;

        int intersection = 0, union_count = 0;
        for (const auto& [w, c] : count_a) {
            union_count += c;
            if (count_b.count(w)) intersection += std::min(c, count_b[w]);
        }
        for (const auto& [w, c] : count_b) {
            if (!count_a.count(w)) union_count += c;
        }

        return union_count > 0 ? static_cast<float>(intersection) / union_count : 0.0f;
    }

    bool is_exact_duplicate(const std::string& url) {
        return std::find(urls.begin(), urls.end(), url) != urls.end();
    }
};

extern "C" {

YALLA_CORE_EXPORT YallaDeduplicatorHandle yalla_deduplicator_create() {
    return new YallaDeduplicator();
}

YALLA_CORE_EXPORT void yalla_deduplicator_destroy(YallaDeduplicatorHandle handle) {
    if (handle) delete static_cast<YallaDeduplicator*>(handle);
}

YALLA_CORE_EXPORT bool yalla_deduplicator_is_duplicate(YallaDeduplicatorHandle handle,
    const YallaArticle* article, float* similarity) {
    if (!handle || !article) return false;
    auto* dedup = static_cast<YallaDeduplicator*>(handle);

    // Check exact URL duplicate
    if (article->url && dedup->is_exact_duplicate(article->url)) {
        if (similarity) *similarity = 1.0f;
        return true;
    }

    // SimHash near-duplicate check (fast)
    uint64_t simhash = dedup->compute_simhash(article);
    int min_hamming = 64;
    for (uint64_t existing : dedup->simhashes) {
        int dist = dedup->hamming_distance(simhash, existing);
        min_hamming = std::min(min_hamming, dist);
    }

    // Hamming distance <= 3 is strong near-duplicate signal
    if (min_hamming <= 3 && !dedup->simhashes.empty()) {
        if (similarity) *similarity = 1.0f - (min_hamming / 64.0f);
        return true;
    }

    // Jaccard similarity for fingerprints (more accurate but slower)
    std::string fp = dedup->compute_fingerprint(article);
    float max_sim = 0.0f;

    for (const auto& existing_fp : dedup->fingerprints) {
        float sim = dedup->jaccard_similarity(fp, existing_fp);
        max_sim = std::max(max_sim, sim);
        if (sim >= dedup->threshold) {
            if (similarity) *similarity = sim;
            return true;
        }
    }

    if (similarity) *similarity = max_sim;
    return false;
}

YALLA_CORE_EXPORT void yalla_deduplicator_add(YallaDeduplicatorHandle handle, const YallaArticle* article) {
    if (!handle || !article) return;
    auto* dedup = static_cast<YallaDeduplicator*>(handle);
    dedup->simhashes.push_back(dedup->compute_simhash(article));
    dedup->fingerprints.push_back(dedup->compute_fingerprint(article));
    if (article->url) dedup->urls.push_back(article->url);
}

YALLA_CORE_EXPORT void yalla_deduplicator_clear(YallaDeduplicatorHandle handle) {
    if (handle) {
        auto* dedup = static_cast<YallaDeduplicator*>(handle);
        dedup->simhashes.clear();
        dedup->fingerprints.clear();
        dedup->urls.clear();
    }
}

YALLA_CORE_EXPORT void yalla_deduplicator_set_threshold(YallaDeduplicatorHandle handle, float threshold) {
    if (handle) static_cast<YallaDeduplicator*>(handle)->threshold = std::clamp(threshold, 0.0f, 1.0f);
}

} // extern "C"