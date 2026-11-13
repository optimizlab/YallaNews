// News Ingestion - Stub implementation
#include "yalla_core.h"
#include <string>

struct YallaNewsIngestion {
    int32_t timeoutMs = 30000;
    int32_t rateLimitRpm = 60;
    std::string modelsDir;

    YallaNewsIngestion(const std::string& dir) : modelsDir(dir) {}
};

extern "C" {

YALLA_CORE_EXPORT YallaNewsIngestionHandle yalla_news_ingestion_create(const char* modelsDir) {
    return new YallaNewsIngestion(modelsDir ? modelsDir : "./models");
}

YALLA_CORE_EXPORT void yalla_news_ingestion_destroy(YallaNewsIngestionHandle handle) {
    if (handle) delete static_cast<YallaNewsIngestion*>(handle);
}

YALLA_CORE_EXPORT bool yalla_news_ingestion_fetchRss(YallaNewsIngestionHandle handle,
    const char* feedUrl, YallaCompletionCallback callback, void* userData) {
    (void)handle; (void)feedUrl; (void)callback; (void)userData;
    return false;
}

YALLA_CORE_EXPORT bool yalla_news_ingestion_fetchAtom(YallaNewsIngestionHandle handle,
    const char* feedUrl, YallaCompletionCallback callback, void* userData) {
    (void)handle; (void)feedUrl; (void)callback; (void)userData;
    return false;
}

YALLA_CORE_EXPORT bool yalla_news_ingestionExtractHtml(YallaNewsIngestionHandle handle,
    const char* url, const char* html, YallaCompletionCallback callback, void* userData) {
    (void)handle; (void)url; (void)html; (void)callback; (void)userData;
    return false;
}

YALLA_CORE_EXPORT void yalla_news_ingestionSetTimeout(YallaNewsIngestionHandle handle, int32_t timeoutMs) {
    if (!handle) return;
    auto* ingestion = static_cast<YallaNewsIngestion*>(handle);
    ingestion->timeoutMs = timeoutMs;
}

YALLA_CORE_EXPORT void yalla_news_ingestionSetRateLimit(YallaNewsIngestionHandle handle, int32_t requestsPerMinute) {
    if (!handle) return;
    auto* ingestion = static_cast<YallaNewsIngestion*>(handle);
    ingestion->rateLimitRpm = requestsPerMinute;
}

} // extern "C"
