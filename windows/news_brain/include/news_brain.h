#ifndef NEWS_BRAIN_H
#define NEWS_BRAIN_H

#include <stdint.h>

#ifdef _WIN32
  #ifdef NEWSBRAIN_EXPORTS
    #define NEWSBRAIN_EXPORT __declspec(dllexport)
  #else
    #define NEWSBRAIN_EXPORT __declspec(dllimport)
  #endif
#else
  #define NEWSBRAIN_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

// Library version string
NEWSBRAIN_EXPORT const char* newsbrain_get_version();

// Free string allocated by newsBrain
NEWSBRAIN_EXPORT void newsbrain_free_string(const char* str);

// Scan a URL directly: Downloads page, creates PageSkeleton, returns JSON string.
// Caller is responsible for freeing the string via newsbrain_free_string().
NEWSBRAIN_EXPORT const char* newsbrain_scan_url(const char* url);

// Scan raw HTML string: Creates PageSkeleton from HTML, returns JSON string.
// Caller is responsible for freeing the string via newsbrain_free_string().
NEWSBRAIN_EXPORT const char* newsbrain_scan_html(const char* html, const char* url);

// Full extraction pipeline for a URL:
// URL -> HTTP Fetch -> HTML Parser -> Page Scanner -> Candidate Detector ->
// Article Brain -> Article Rebuilder -> NewsArticle JSON.
// Caller is responsible for freeing the string via newsbrain_free_string().
NEWSBRAIN_EXPORT const char* newsbrain_extract_article_url(const char* url);

// Full extraction pipeline for raw HTML:
// HTML -> HTML Parser -> Page Scanner -> Candidate Detector ->
// Article Brain -> Article Rebuilder -> NewsArticle JSON.
// Caller is responsible for freeing the string via newsbrain_free_string().
NEWSBRAIN_EXPORT const char* newsbrain_extract_article_html(const char* html, const char* url);

// Pluggable HTTP fetcher callback for platforms (Android, iOS)
// If set, newsbrain will invoke this function to fetch HTML over HTTP/HTTPS.
// The callback returns a null-terminated UTF-8 string containing HTML or nullptr on error.
typedef const char* (*NewsBrainHttpFetchCallback)(const char* url);
NEWSBRAIN_EXPORT void newsbrain_set_http_fetcher(NewsBrainHttpFetchCallback callback);

// Classify an article and return NLP results as JSON string.
// Caller is responsible for freeing the string via newsbrain_free_string().
// JSON fields: category, subcategory, sentiment, event_type, keywords, entities, confidence
NEWSBRAIN_EXPORT const char* newsbrain_classify_article(const char* title, const char* content, const char* summary);

// Get just the category for an article.
// Caller is responsible for freeing the string via newsbrain_free_string().
NEWSBRAIN_EXPORT const char* newsbrain_classify_category(const char* title, const char* content, const char* summary);

// Analyze sentiment of a text block.
// Returns a double value between -1.0 (negative) and 1.0 (positive).
NEWSBRAIN_EXPORT double newsbrain_analyze_sentiment(const char* text);

// Score whether an extracted page is a real news article (0.0 to 1.0).
NEWSBRAIN_EXPORT double newsbrain_score_article_quality(const char* title, const char* content, const char* summary);

#ifdef __cplusplus
}
#endif

#endif // NEWS_BRAIN_H
