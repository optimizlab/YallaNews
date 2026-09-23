#ifndef YALLA_ENGINE_H
#define YALLA_ENGINE_H

#include "cluster.h"

#ifdef _WIN32
  #define YALLA_EXPORT __declspec(dllexport)
#else
  #define YALLA_EXPORT __attribute__((visibility("default")))
#endif

extern "C" {

// Initialize the C++ engine (loads any assets, DBs or initializes local states)
YALLA_EXPORT void init_engine(const char* db_content_json);

// Process a URL through the 4-stage C++ engine pipeline (Crawler -> Miner -> DeepAnalyser -> TinyLLM)
// Returns a dynamically-allocated JSON string containing:
// {
//   "success": true/false,
//   "title": "...",
//   "summary": "...",
//   "content": "...",
//   "category": "...",
//   "sentiment": 0.85,
//   "keywords": ["...", "..."],
//   "logs": "..."
// }
// The caller is responsible for calling free_string to avoid memory leaks.
YALLA_EXPORT const char* process_url(const char* url);

// Free memory allocated by the C++ engine for strings returned to Dart FFI
YALLA_EXPORT void free_string(const char* str);

// Retrieve accumulator logs directly (for FFI log streaming support)
YALLA_EXPORT const char* get_engine_logs();

// Clear accumulator logs
YALLA_EXPORT void clear_engine_logs();

// Full NLP analysis of article text — returns structured JSON
YALLA_EXPORT const char* analyze_article(const char* json_input);

// Clustering APIs - pass JSON array of articles, get clustered groups back
// algorithm: 0=k-means, 1=dbscan, 2=hierarchical
// n_clusters: number of clusters (for k-means/hierarchical, auto-calculated if 0)
// eps: epsilon for DBSCAN
// min_samples: minimum samples for DBSCAN
YALLA_EXPORT const char* cluster_articles_ex(
    const char* json_input,
    int32_t algorithm,
    int32_t n_clusters,
    double eps,
    int32_t min_samples
);

// Free cluster output string
YALLA_EXPORT void free_cluster_string(const char* str);

// Validate an image URL: returns 1 if valid, 0 if invalid.
// Rejects non-http(s), data URIs, blacklisted extensions, and blacklisted keywords.
YALLA_EXPORT int is_valid_image_url(const char* url);

// Split article content into dot-based segments (sentences/paragraphs).
// Returns a JSON array of strings. Caller must call free_string on the returned pointer.
YALLA_EXPORT const char* split_paragraphs_by_dots(const char* content);

// Clean article content using TinyLLM-style filtering:
// - removes text out of the context of title + global context
// - removes gabredge text not linked to the active news story
// - normalizes references so content reads as a coherent story
// Returns a newly allocated JSON string: {"cleaned_content": "...", "removed_segments": [...]}.
// Caller must call free_string on the returned pointer.
YALLA_EXPORT const char* clean_article_content(const char* title, const char* content);

// Extract structured story elements from article text:
// - key persons
// - key dates
// - key events
// Returns a newly allocated JSON string:
// {"persons": [...], "dates": [...], "events": [...]}.
// Caller must call free_string on the returned pointer.
YALLA_EXPORT const char* extract_story_elements(const char* title, const char* content);

// Optimized sentiment analysis for news content.
// Returns a double value between -1.0 and 1.0.
YALLA_EXPORT double optimize_sentiment(const char* text);

}

#endif // YALLA_ENGINE_H
