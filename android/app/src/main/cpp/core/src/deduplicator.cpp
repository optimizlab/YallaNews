// Deduplicator - Simplified stub implementation
// Provides exact and near-duplicate detection for news articles

#include "yalla_core.h"
#include <string>
#include <vector>
#include <algorithm>
#include <cmath>
#include <sstream>
#include <random>
#include <cstdint>

struct YallaDeduplicator {
    float threshold = 0.85f;
    std::vector<std::string> fingerprints;  // Fingerprints for near-duplicate detection
    std::vector<std::string> urls;  // Track URLs for exact match

    std::string compute_fingerprint(const YallaArticle* article) {
        std::string combined;
        if (article->title) combined += article->title;
        combined += " ";
        if (article->content) combined += article->content;

        std::transform(combined.begin(), combined.end(), combined.begin(),
            [](unsigned char c) { return std::tolower(c); });

        // Simple word-based fingerprint
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
        for (size_t i = 0; i < words.size() && i < 50; ++i) {
            if (i > 0) fp += " ";
            fp += words[i];
        }
        return fp;
    }

    bool is_duplicate(const YallaArticle* article) {
        // Check exact URL duplicate first
        if (article->url) {
            for (const auto& u : urls) {
                if (u == article->url) return true;
            }
        }

        // Check fingerprint similarity
        std::string fp = compute_fingerprint(article);
        for (const auto& existing : fingerprints) {
            if (jaccard_similarity(fp, existing) >= threshold) {
                return true;
            }
        }

        // Store this article's fingerprint
        fingerprints.push_back(fp);
        if (article->url) urls.push_back(article->url);
        return false;
    }

    float jaccard_similarity(const std::string& a, const std::string& b) {
        std::istringstream issa(a), issb(b);
        std::vector<std::string> words_a, words_b;
        std::string word;
        while (issa >> word) words_a.push_back(word);
        while (issb >> word) words_b.push_back(word);

        std::sort(words_a.begin(), words_a.end());
        words_a.erase(std::unique(words_a.begin(), words_a.end()), words_a.end());
        std::sort(words_b.begin(), words_b.end());
        words_b.erase(std::unique(words_b.begin(), words_b.end()), words_b.end());

        int intersection = 0;
        size_t i = 0, j = 0;
        while (i < words_a.size() && j < words_b.size()) {
            if (words_a[i] == words_b[j]) {
                intersection++;
                i++;
                j++;
            } else if (words_a[i] < words_b[j]) {
                i++;
            } else {
                j++;
            }
        }

        int total = words_a.size() + words_b.size() - intersection;
        return total > 0 ? static_cast<float>(intersection) / total : 0.0f;
    }
};
