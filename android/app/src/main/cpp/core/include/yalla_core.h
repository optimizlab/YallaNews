#ifndef YALLA_CORE_H
#define YALLA_CORE_H

#include <cstdint>
#include <string>
#include <vector>
#include <memory>
#include <functional>

#ifdef _WIN32
  #define YALLA_CORE_EXPORT __declspec(dllexport)
#else
  #define YALLA_CORE_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

// ============================================================================
// Core Types
// ============================================================================

// Opaque handles for C API
typedef struct YallaTaskScheduler* YallaTaskSchedulerHandle;
typedef struct YallaNewsIngestion* YallaNewsIngestionHandle;
typedef struct YallaLanguageDetector* YallaLanguageDetectorHandle;
typedef struct YallaDeduplicator* YallaDeduplicatorHandle;
typedef struct YallaClassifier* YallaClassifierHandle;
typedef struct YallaEntityExtractor* YallaEntityExtractorHandle;
typedef struct YallaEventClusterer* YallaEventClustererHandle;
typedef struct YallaModelManager* YallaModelManagerHandle;
typedef struct YallaInferenceEngine* YallaInferenceEngineHandle;
typedef struct YallaSummarizer* YallaSummarizerHandle;
typedef struct YallaTranslator* YallaTranslatorHandle;
typedef struct NewsPipeline* NewsPipelineHandle;

// Language codes
typedef enum {
    YALLA_LANG_UNKNOWN = 0,
    YALLA_LANG_ARABIC  = 1,
    YALLA_LANG_ENGLISH = 2,
    YALLA_LANG_FRENCH  = 3
} YallaLanguage;

// Article structure for C API
typedef struct {
    const char* url;
    const char* title;
    const char* summary;
    const char* content;
    const char* image_url;
    const char* category;
    double sentiment;
    const char* keywords;  // comma-separated
    const char* language;
    int64_t publish_date;  // milliseconds since epoch
    const char* author;
    const char* source_url;
} YallaArticle;

// Entity structure
typedef struct {
    const char* type;
    const char* value;
    const char* canonical;
    const char* language;
    double confidence;
} YallaEntity;

// Event structure
typedef struct {
    const char* id;
    const char* label;
    const char* date;
    const char* location;
    const char* actors_json;
    const char* evidence_json;
    double confidence;
    int64_t extracted_at;
} YallaEvent;

// Clustering result
typedef struct {
    int32_t cluster_id;
    const char** article_urls;
    int32_t article_count;
    const char* centroid_keywords;
} YallaCluster;

// AI Model info
typedef struct {
    const char* model_id;
    const char* version;
    const char* quantization;
    int64_t size_bytes;
    const char* checksum;
    const char* hardware_profile;  // "low", "medium", "high"
} YallaModelInfo;

// Inference request/response
typedef struct {
    const char* prompt;
    int32_t max_tokens;
    float temperature;
    float top_p;
    bool stream;
} YallaInferenceRequest;

typedef struct {
    const char* text;
    int32_t tokens_used;
    bool truncated;
    const char* error;
} YallaInferenceResponse;

// Callback types
typedef void (*YallaProgressCallback)(int32_t progress, const char* message, void* user_data);
typedef void (*YallaLogCallback)(const char* level, const char* message, void* user_data);
typedef void (*YallaCompletionCallback)(bool success, const char* result_json, void* user_data);

// ============================================================================
// Task Scheduler
// ============================================================================

YALLA_CORE_EXPORT YallaTaskSchedulerHandle yalla_task_scheduler_create(int32_t max_concurrent_tasks);
YALLA_CORE_EXPORT void yalla_task_scheduler_destroy(YallaTaskSchedulerHandle handle);
YALLA_CORE_EXPORT bool yalla_task_scheduler_submit(YallaTaskSchedulerHandle handle,
    const char* task_json, YallaCompletionCallback callback, void* user_data);
YALLA_CORE_EXPORT void yalla_task_scheduler_cancel_all(YallaTaskSchedulerHandle handle);
YALLA_CORE_EXPORT int32_t yalla_task_scheduler_pending_count(YallaTaskSchedulerHandle handle);

// ============================================================================
// News Ingestion (RSS, Atom, HTML extraction)
// ============================================================================

YALLA_CORE_EXPORT YallaNewsIngestionHandle yalla_news_ingestion_create(const char* modelsDir);
YALLA_CORE_EXPORT void yalla_news_ingestion_destroy(YallaNewsIngestionHandle handle);
YALLA_CORE_EXPORT bool yalla_news_ingestion_fetch_rss(YallaNewsIngestionHandle handle,
    const char* feed_url, YallaCompletionCallback callback, void* user_data);
YALLA_CORE_EXPORT bool yalla_news_ingestion_fetch_atom(YallaNewsIngestionHandle handle,
    const char* feed_url, YallaCompletionCallback callback, void* user_data);
YALLA_CORE_EXPORT bool yalla_news_ingestion_extract_html(YallaNewsIngestionHandle handle,
    const char* url, const char* html, YallaCompletionCallback callback, void* user_data);
YALLA_CORE_EXPORT void yalla_news_ingestion_set_timeout(YallaNewsIngestionHandle handle, int32_t timeout_ms);
YALLA_CORE_EXPORT void yalla_news_ingestion_set_rate_limit(YallaNewsIngestionHandle handle, int32_t requests_per_minute);

// ============================================================================
// Language Detection & Normalization
// ============================================================================

YALLA_CORE_EXPORT YallaLanguageDetectorHandle yalla_language_detector_create();
YALLA_CORE_EXPORT void yalla_language_detector_destroy(YallaLanguageDetectorHandle handle);
YALLA_CORE_EXPORT YallaLanguage yalla_language_detector_detect(YallaLanguageDetectorHandle handle,
    const char* text, float* confidence);
YALLA_CORE_EXPORT const char* yalla_language_detector_normalize(YallaLanguageDetectorHandle handle,
    YallaLanguage lang, const char* text);

// ============================================================================
// Deduplication (Exact + Near-duplicate)
// ============================================================================

YALLA_CORE_EXPORT YallaDeduplicatorHandle yalla_deduplicator_create();
YALLA_CORE_EXPORT void yalla_deduplicator_destroy(YallaDeduplicatorHandle handle);
YALLA_CORE_EXPORT bool yalla_deduplicator_is_duplicate(YallaDeduplicatorHandle handle,
    const YallaArticle* article, float* similarity);
YALLA_CORE_EXPORT void yalla_deduplicator_add(YallaDeduplicatorHandle handle, const YallaArticle* article);
YALLA_CORE_EXPORT void yalla_deduplicator_clear(YallaDeduplicatorHandle handle);
YALLA_CORE_EXPORT void yalla_deduplicator_set_threshold(YallaDeduplicatorHandle handle, float threshold);

// ============================================================================
// Classification
// ============================================================================

YALLA_CORE_EXPORT YallaClassifierHandle yalla_classifier_create();
YALLA_CORE_EXPORT void yalla_classifier_destroy(YallaClassifierHandle handle);
YALLA_CORE_EXPORT const char* yalla_classifier_classify(YallaClassifierHandle handle,
    const char* title, const char* content, const char* summary, float* confidence);
YALLA_CORE_EXPORT const char* yalla_classifier_get_subcategory(YallaClassifierHandle handle,
    const char* title, const char* content, const char* summary);

// ============================================================================
// Entity Extraction
// ============================================================================

YALLA_CORE_EXPORT YallaEntityExtractorHandle yalla_entity_extractor_create();
YALLA_CORE_EXPORT void yalla_entity_extractor_destroy(YallaEntityExtractorHandle handle);
YALLA_CORE_EXPORT YallaEntity* yalla_entity_extractor_extract(YallaEntityExtractorHandle handle,
    const char* title, const char* content, const char* language, int32_t* count);
YALLA_CORE_EXPORT void yalla_entity_extractor_free_entities(YallaEntity* entities, int32_t count);

// ============================================================================
// Event Clustering
// ============================================================================

YALLA_CORE_EXPORT YallaEventClustererHandle yalla_event_clusterer_create();
YALLA_CORE_EXPORT void yalla_event_clusterer_destroy(YallaEventClustererHandle handle);
YALLA_CORE_EXPORT YallaCluster* yalla_event_clusterer_cluster(YallaEventClustererHandle handle,
    const YallaArticle* articles, int32_t article_count, int32_t* cluster_count);
YALLA_CORE_EXPORT YallaCluster* yalla_event_clusterer_cluster_ex(YallaEventClustererHandle handle,
    const YallaArticle* articles, int32_t article_count, int32_t algorithm,
    int32_t n_clusters, double eps, int32_t min_samples, int32_t* cluster_count);
YALLA_CORE_EXPORT void yalla_event_clusterer_free_clusters(YallaCluster* clusters, int32_t count);

// ============================================================================
// Model Manager (llama.cpp integration)
// ============================================================================

YALLA_CORE_EXPORT YallaModelManagerHandle yalla_model_manager_create(const char* models_dir);
YALLA_CORE_EXPORT void yalla_model_manager_destroy(YallaModelManagerHandle handle);
YALLA_CORE_EXPORT bool yalla_model_manager_download(YallaModelManagerHandle handle,
    const char* model_id, const char* url, const char* expected_checksum,
    YallaProgressCallback progress_cb, void* user_data);
YALLA_CORE_EXPORT bool yalla_model_manager_verify(YallaModelManagerHandle handle,
    const char* model_id, bool* verified);
YALLA_CORE_EXPORT YallaModelInfo* yalla_model_manager_get_info(YallaModelManagerHandle handle,
    const char* model_id);
YALLA_CORE_EXPORT void yalla_model_manager_free_info(YallaModelInfo* info);
YALLA_CORE_EXPORT const char** yalla_model_manager_list_models(YallaModelManagerHandle handle,
    int32_t* count);
YALLA_CORE_EXPORT void yalla_model_manager_free_list(const char** list, int32_t count);
YALLA_CORE_EXPORT void yalla_model_manager_unload(YallaModelManagerHandle handle, const char* model_id);
YALLA_CORE_EXPORT int64_t yalla_model_manager_get_memory_usage(YallaModelManagerHandle handle);

// ============================================================================
// Inference Engine
// ============================================================================

YALLA_CORE_EXPORT YallaInferenceEngineHandle yalla_inference_engine_create(YallaModelManagerHandle model_manager);
YALLA_CORE_EXPORT void yalla_inference_engine_destroy(YallaInferenceEngineHandle handle);
YALLA_CORE_EXPORT bool yalla_inference_engine_load_model(YallaInferenceEngineHandle handle,
    const char* model_id, int32_t context_size, int32_t max_batch_size);
YALLA_CORE_EXPORT void yalla_inference_engine_unload_model(YallaInferenceEngineHandle handle);
YALLA_CORE_EXPORT YallaInferenceResponse yalla_inference_engine_infer(YallaInferenceEngineHandle handle,
    const YallaInferenceRequest* request);
YALLA_CORE_EXPORT void yalla_inference_engine_cancel(YallaInferenceEngineHandle handle);
YALLA_CORE_EXPORT bool yalla_inference_engine_is_busy(YallaInferenceEngineHandle handle);
YALLA_CORE_EXPORT int64_t yalla_inference_engine_get_memory_usage(YallaInferenceEngineHandle handle);

// ============================================================================
// Summarization
// ============================================================================

YALLA_CORE_EXPORT YallaSummarizerHandle yalla_summarizer_create(YallaInferenceEngineHandle engine);
YALLA_CORE_EXPORT void yalla_summarizer_destroy(YallaSummarizerHandle handle);
YALLA_CORE_EXPORT const char* yalla_summarizer_summarize(YallaSummarizerHandle handle,
    const char* title, const char* content, const char* language, int32_t max_length);
YALLA_CORE_EXPORT const char* yalla_summarizer_summarize_batch(YallaSummarizerHandle handle,
    const char** titles, const char** contents, int32_t count, const char* language, int32_t max_length);

// ============================================================================
// Translation
// ============================================================================

YALLA_CORE_EXPORT YallaTranslatorHandle yalla_translator_create(YallaInferenceEngineHandle engine);
YALLA_CORE_EXPORT void yalla_translator_destroy(YallaTranslatorHandle handle);
YALLA_CORE_EXPORT const char* yalla_translator_translate(YallaTranslatorHandle handle,
    const char* text, YallaLanguage source_lang, YallaLanguage target_lang);
YALLA_CORE_EXPORT const char* yalla_translator_translate_batch(YallaTranslatorHandle handle,
    const char** texts, int32_t count, YallaLanguage source_lang, YallaLanguage target_lang);

// ============================================================================
// Utility Functions
// ============================================================================

YALLA_CORE_EXPORT void yalla_free_string(const char* str);
YALLA_CORE_EXPORT void yalla_free_article(YallaArticle* article);
YALLA_CORE_EXPORT const char* yalla_get_version();
YALLA_CORE_EXPORT void yalla_set_log_callback(YallaLogCallback callback, void* user_data);

// ============================================================================
// External Provider Adapters
// ============================================================================

// Provider types
typedef enum {
    YALLA_PROVIDER_RSS = 0,
    YALLA_PROVIDER_ATOM = 1,
    YALLA_PROVIDER_GDELT = 2,
    YALLA_PROVIDER_FACTCHECK = 3,
    YALLA_PROVIDER_WIKIMEDIA = 4,
    YALLA_PROVIDER_CUSTOM = 100
} YallaProviderType;

// Provider article structure (extends YallaArticle with provider metadata)
typedef struct {
    const char* url;
    const char* title;
    const char* summary;
    const char* content;
    const char* image_url;
    const char* category;
    double sentiment;
    const char* keywords;
    const char* language;
    int64_t publish_date;
    const char* author;
    const char* source_url;
    // Provider metadata
    const char* provider_id;
    const char* provider_name;
    const char* license;
    const char* attribution_url;
    const char* raw_provider_data; // JSON string with provider-specific fields
} YallaProviderArticle;

// Provider configuration
typedef struct {
    YallaProviderType type;
    const char* provider_id;
    const char* api_key;       // For APIs requiring keys
    const char* base_url;      // Override default endpoint
    int32_t timeout_ms;
    int32_t rate_limit_rpm;
    int32_t max_retries;
    const char* custom_params; // JSON string for provider-specific config
} YallaProviderConfig;

// Opaque handle for provider adapter
typedef struct YallaProviderAdapter* YallaProviderAdapterHandle;

// Provider result
typedef struct {
    bool success;
    const char* error_message;
    YallaProviderArticle* articles;
    int32_t article_count;
    int64_t next_cursor; // For pagination
} YallaProviderResult;

YALLA_CORE_EXPORT YallaProviderAdapterHandle yalla_provider_adapter_create(const YallaProviderConfig* config);
YALLA_CORE_EXPORT void yalla_provider_adapter_destroy(YallaProviderAdapterHandle handle);
YALLA_CORE_EXPORT YallaProviderResult yalla_provider_adapter_fetch(YallaProviderAdapterHandle handle,
    const char* query, int32_t max_results);
YALLA_CORE_EXPORT YallaProviderResult yalla_provider_adapter_fetch_latest(YallaProviderAdapterHandle handle,
    int32_t max_results);
YALLA_CORE_EXPORT void yalla_provider_adapter_free_result(YallaProviderResult* result);
YALLA_CORE_EXPORT const char** yalla_provider_list_supported(int32_t* count);
YALLA_CORE_EXPORT void yalla_provider_free_list(const char** list, int32_t count);

// ============================================================================
// News Intelligence Pipeline
// ============================================================================

YALLA_CORE_EXPORT NewsPipelineHandle yalla_pipeline_create(const char* config_json);
YALLA_CORE_EXPORT void yalla_pipeline_destroy(NewsPipelineHandle handle);
YALLA_CORE_EXPORT const char* yalla_pipeline_run(NewsPipelineHandle handle);
YALLA_CORE_EXPORT void yalla_pipeline_set_progress_callback(NewsPipelineHandle handle,
    void (*callback)(const char* stage, int32_t progress, const char* message));
YALLA_CORE_EXPORT void yalla_pipeline_set_completion_callback(NewsPipelineHandle handle,
    void (*callback)(const char* result_json));

#ifdef __cplusplus
}
#endif

// ============================================================================
// C++ API (inline implementations)
// ============================================================================

#ifdef __cplusplus
#include <string>
#include <vector>
#include <optional>

namespace yalla {

// RAII wrappers for C handles
class TaskScheduler {
    YallaTaskSchedulerHandle handle_;
public:
    explicit TaskScheduler(int max_concurrent = 4) : handle_(yalla_task_scheduler_create(max_concurrent)) {}
    ~TaskScheduler() { if (handle_) yalla_task_scheduler_destroy(handle_); }
    TaskScheduler(const TaskScheduler&) = delete;
    TaskScheduler& operator=(const TaskScheduler&) = delete;
    TaskScheduler(TaskScheduler&& other) noexcept : handle_(other.handle_) { other.handle_ = nullptr; }
    TaskScheduler& operator=(TaskScheduler&& other) noexcept {
        if (handle_) yalla_task_scheduler_destroy(handle_);
        handle_ = other.handle_; other.handle_ = nullptr; return *this;
    }
    bool submit(const std::string& task_json, std::function<void(bool, const std::string&)> callback) {
        // Implementation would need a trampoline for the C callback
        return false;
    }
    int32_t pending_count() const { return yalla_task_scheduler_pending_count(handle_); }
    void cancel_all() { yalla_task_scheduler_cancel_all(handle_); }
};

class LanguageDetector {
    YallaLanguageDetectorHandle handle_;
public:
    LanguageDetector() : handle_(yalla_language_detector_create()) {}
    ~LanguageDetector() { if (handle_) yalla_language_detector_destroy(handle_); }
    LanguageDetector(const LanguageDetector&) = delete;
    LanguageDetector& operator=(const LanguageDetector&) = delete;
    std::pair<YallaLanguage, float> detect(const std::string& text) {
        float conf = 0;
        auto lang = yalla_language_detector_detect(handle_, text.c_str(), &conf);
        return {lang, conf};
    }
    std::string normalize(YallaLanguage lang, const std::string& text) {
        const char* result = yalla_language_detector_normalize(handle_, lang, text.c_str());
        std::string str(result ? result : "");
        yalla_free_string(result);
        return str;
    }
};

class Deduplicator {
    YallaDeduplicatorHandle handle_;
public:
    Deduplicator() : handle_(yalla_deduplicator_create()) {}
    ~Deduplicator() { if (handle_) yalla_deduplicator_destroy(handle_); }
    Deduplicator(const Deduplicator&) = delete;
    Deduplicator& operator=(const Deduplicator&) = delete;
    bool is_duplicate(const YallaArticle* article, float* similarity) {
        return yalla_deduplicator_is_duplicate(handle_, article, similarity);
    }
    void add(const YallaArticle* article) { yalla_deduplicator_add(handle_, article); }
    void clear() { yalla_deduplicator_clear(handle_); }
    void set_threshold(float t) { yalla_deduplicator_set_threshold(handle_, t); }
};

class Classifier {
    YallaClassifierHandle handle_;
public:
    Classifier() : handle_(yalla_classifier_create()) {}
    ~Classifier() { if (handle_) yalla_classifier_destroy(handle_); }
    Classifier(const Classifier&) = delete;
    Classifier& operator=(const Classifier&) = delete;
    std::pair<std::string, float> classify(const std::string& title, const std::string& content, const std::string& summary) {
        float conf = 0;
        const char* result = yalla_classifier_classify(handle_, title.c_str(), content.c_str(), summary.c_str(), &conf);
        std::string cat(result ? result : "");
        yalla_free_string(result);
        return {cat, conf};
    }
    std::string get_subcategory(const std::string& title, const std::string& content, const std::string& summary) {
        const char* result = yalla_classifier_get_subcategory(handle_, title.c_str(), content.c_str(), summary.c_str());
        std::string cat(result ? result : "");
        yalla_free_string(result);
        return cat;
    }
};

class EntityExtractor {
    YallaEntityExtractorHandle handle_;
public:
    EntityExtractor() : handle_(yalla_entity_extractor_create()) {}
    ~EntityExtractor() { if (handle_) yalla_entity_extractor_destroy(handle_); }
    EntityExtractor(const EntityExtractor&) = delete;
    EntityExtractor& operator=(const EntityExtractor&) = delete;
    std::vector<YallaEntity> extract(const std::string& title, const std::string& content, const std::string& language) {
        int32_t count = 0;
        YallaEntity* entities = yalla_entity_extractor_extract(handle_, title.c_str(), content.c_str(), language.c_str(), &count);
        std::vector<YallaEntity> result;
        for (int i = 0; i < count; ++i) result.push_back(entities[i]);
        yalla_entity_extractor_free_entities(entities, count);
        return result;
    }
};

class EventClusterer {
    YallaEventClustererHandle handle_;
public:
    EventClusterer() : handle_(yalla_event_clusterer_create()) {}
    ~EventClusterer() { if (handle_) yalla_event_clusterer_destroy(handle_); }
    EventClusterer(const EventClusterer&) = delete;
    EventClusterer& operator=(const EventClusterer&) = delete;
    std::vector<YallaCluster> cluster(const std::vector<YallaArticle>& articles) {
        int32_t count = 0;
        YallaCluster* clusters = yalla_event_clusterer_cluster(handle_, articles.data(), articles.size(), &count);
        std::vector<YallaCluster> result;
        for (int i = 0; i < count; ++i) result.push_back(clusters[i]);
        yalla_event_clusterer_free_clusters(clusters, count);
        return result;
    }
    std::vector<YallaCluster> cluster_ex(const std::vector<YallaArticle>& articles,
        int32_t algorithm, int32_t n_clusters, double eps, int32_t min_samples) {
        int32_t count = 0;
        YallaCluster* clusters = yalla_event_clusterer_cluster_ex(handle_, articles.data(), articles.size(),
            algorithm, n_clusters, eps, min_samples, &count);
        std::vector<YallaCluster> result;
        for (int i = 0; i < count; ++i) result.push_back(clusters[i]);
        yalla_event_clusterer_free_clusters(clusters, count);
        return result;
    }
};

// Provider Adapter
class ProviderAdapter {
    YallaProviderAdapterHandle handle_;
public:
    explicit ProviderAdapter(const YallaProviderConfig& config) : handle_(yalla_provider_adapter_create(&config)) {}
    ~ProviderAdapter() { if (handle_) yalla_provider_adapter_destroy(handle_); }
    ProviderAdapter(const ProviderAdapter&) = delete;
    ProviderAdapter& operator=(const ProviderAdapter&) = delete;

    std::vector<YallaProviderArticle> fetch(const std::string& query, int32_t max_results = 50) {
        YallaProviderResult result = yalla_provider_adapter_fetch(handle_, query.c_str(), max_results);
        std::vector<YallaProviderArticle> articles;
        if (result.success && result.articles && result.article_count > 0) {
            articles.reserve(result.article_count);
            for (int i = 0; i < result.article_count; ++i) {
                articles.push_back(result.articles[i]);
            }
        }
        yalla_provider_adapter_free_result(&result);
        return articles;
    }

    std::vector<YallaProviderArticle> fetch_latest(int32_t max_results = 50) {
        YallaProviderResult result = yalla_provider_adapter_fetch_latest(handle_, max_results);
        std::vector<YallaProviderArticle> articles;
        if (result.success && result.articles && result.article_count > 0) {
            articles.reserve(result.article_count);
            for (int i = 0; i < result.article_count; ++i) {
                articles.push_back(result.articles[i]);
            }
        }
        yalla_provider_adapter_free_result(&result);
        return articles;
    }
};

// Provider Registry
class ProviderRegistry {
public:
    static std::vector<std::string> list_supported() {
        int32_t count = 0;
        const char** list = yalla_provider_list_supported(&count);
        std::vector<std::string> result;
        if (list) {
            result.reserve(count);
            for (int i = 0; i < count; ++i) {
                if (list[i]) result.push_back(list[i]);
            }
            yalla_provider_free_list(list, count);
        }
        return result;
    }
};

// News Pipeline
class NewsPipeline {
    NewsPipelineHandle handle_;
public:
    explicit NewsPipeline(const std::string& config_json) : handle_(yalla_pipeline_create(config_json.c_str())) {}
    ~NewsPipeline() { if (handle_) yalla_pipeline_destroy(handle_); }
    NewsPipeline(const NewsPipeline&) = delete;
    NewsPipeline& operator=(const NewsPipeline&) = delete;
    NewsPipeline(NewsPipeline&& other) noexcept : handle_(other.handle_) { other.handle_ = nullptr; }
    NewsPipeline& operator=(NewsPipeline&& other) noexcept {
        if (handle_) yalla_pipeline_destroy(handle_);
        handle_ = other.handle_; other.handle_ = nullptr; return *this;
    }
    
    std::string run() {
        const char* result = yalla_pipeline_run(handle_);
        std::string str(result ? result : "");
        yalla_free_string(result);
        return str;
    }
    
    void set_progress_callback(void (*callback)(const char* stage, int32_t progress, const char* message)) {
        yalla_pipeline_set_progress_callback(handle_, callback);
    }
    
    void set_completion_callback(void (*callback)(const char* result_json)) {
        yalla_pipeline_set_completion_callback(handle_, callback);
    }
};

} // namespace yalla
#endif // __cplusplus

#endif // YALLA_CORE_H