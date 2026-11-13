#include "yalla_core.h"
#include <string>
#include <vector>
#include <memory>
#include <thread>
#include <mutex>
#include <condition_variable>
#include <queue>
#include <functional>
#include <chrono>
#include <atomic>
#include <nlohmann/json.hpp>
#include <unordered_map>
#include <set>

using json = nlohmann::json;

// Forward declarations for RAII wrappers
namespace yalla {
    class TaskScheduler;
    class LanguageDetector;
    class Deduplicator;
    class Classifier;
    class EntityExtractor;
    class EventClusterer;
    class Summarizer;
    class Translator;
    class ProviderAdapter;
}

// ============================================================================
// Pipeline Data Structures
// ============================================================================

struct PipelineArticle {
    std::string url;
    std::string title;
    std::string summary;
    std::string content;
    std::string image_url;
    std::string category;
    double sentiment = 0.0;
    std::vector<std::string> keywords;
    std::string language;
    int64_t publish_date = 0;
    std::string author;
    std::string source_url;
    
    // Provider metadata
    std::string provider_id;
    std::string provider_name;
    std::string license;
    std::string attribution_url;
    json raw_provider_data;
    
    // Processing results
    std::string normalized_title;
    std::string normalized_content;
    std::string ai_summary;
    std::unordered_map<std::string, std::string> translations; // lang -> text
    std::vector<YallaEntity> entities;
    std::string subcategory;
    int32_t cluster_id = -1;
    bool is_duplicate = false;
    float duplicate_similarity = 0.0f;
    bool verified = false;
    std::string verification_source;
    float relevance_score = 0.0f;
    
    json to_json() const {
        json j;
        j["url"] = url;
        j["title"] = title;
        j["summary"] = summary;
        j["content"] = content;
        j["image_url"] = image_url;
        j["category"] = category;
        j["sentiment"] = sentiment;
        j["keywords"] = keywords;
        j["language"] = language;
        j["publish_date"] = publish_date;
        j["author"] = author;
        j["source_url"] = source_url;
        j["provider_id"] = provider_id;
        j["provider_name"] = provider_name;
        j["license"] = license;
        j["attribution_url"] = attribution_url;
        j["raw_provider_data"] = raw_provider_data;
        j["normalized_title"] = normalized_title;
        j["normalized_content"] = normalized_content;
        j["ai_summary"] = ai_summary;
        j["translations"] = translations;
        j["entities"] = json::array();
        for (const auto& e : entities) {
            j["entities"].push_back({
                {"type", e.type}, {"value", e.value}, {"canonical", e.canonical},
                {"language", e.language}, {"confidence", e.confidence}
            });
        }
        j["subcategory"] = subcategory;
        j["cluster_id"] = cluster_id;
        j["is_duplicate"] = is_duplicate;
        j["duplicate_similarity"] = duplicate_similarity;
        j["verified"] = verified;
        j["verification_source"] = verification_source;
        j["relevance_score"] = relevance_score;
        return j;
    }
};

void from_json(const json& j, PipelineArticle& a) {
    a.url = j.value("url", "");
    a.title = j.value("title", "");
    a.summary = j.value("summary", "");
    a.content = j.value("content", "");
    a.image_url = j.value("image_url", "");
    a.category = j.value("category", "");
    a.sentiment = j.value("sentiment", 0.0);
    a.keywords = j.value("keywords", std::vector<std::string>{});
    a.language = j.value("language", "");
    a.publish_date = j.value("publish_date", int64_t(0));
    a.author = j.value("author", "");
    a.source_url = j.value("source_url", "");
    a.provider_id = j.value("provider_id", "");
    a.provider_name = j.value("provider_name", "");
    a.license = j.value("license", "");
    a.attribution_url = j.value("attribution_url", "");
    a.raw_provider_data = j.value("raw_provider_data", json{});
    a.normalized_title = j.value("normalized_title", "");
    a.normalized_content = j.value("normalized_content", "");
    a.ai_summary = j.value("ai_summary", "");
    a.translations = j.value("translations", std::unordered_map<std::string, std::string>{});
    if (j.contains("entities") && j["entities"].is_array()) {
        for (const auto& e : j["entities"]) {
            YallaEntity entity{};
            entity.type = e.value("type", "").c_str();
            entity.value = e.value("value", "").c_str();
            entity.canonical = e.value("canonical", "").c_str();
            entity.language = e.value("language", "").c_str();
            entity.confidence = e.value("confidence", 0.0);
            a.entities.push_back(entity);
        }
    }
    a.subcategory = j.value("subcategory", "");
    a.cluster_id = j.value("cluster_id", -1);
    a.is_duplicate = j.value("is_duplicate", false);
    a.duplicate_similarity = j.value("duplicate_similarity", 0.0f);
    a.verified = j.value("verified", false);
    a.verification_source = j.value("verification_source", "");
    a.relevance_score = j.value("relevance_score", 0.0f);
}

struct PipelineConfig {
    // Discovery
    std::vector<YallaProviderConfig> providers;
    int32_t max_articles_per_provider = 50;
    std::vector<std::string> rss_feeds;
    
    // Processing
    bool enable_dedup = true;
    float dedup_threshold = 0.85f;
    bool enable_classification = true;
    bool enable_entities = true;
    bool enable_clustering = true;
    int32_t cluster_algorithm = 1; // DBSCAN
    double cluster_eps = 0.5;
    int32_t cluster_min_samples = 2;
    
    // AI
    bool enable_ai = true;
    std::string ai_model = "qwen3-0.6b-q4";
    int32_t ai_context_size = 4096;
    bool enable_summarization = true;
    int32_t summary_max_length = 150;
    bool enable_translation = true;
    std::vector<std::string> target_languages = {"ar", "en", "fr"};
    
    // Verification
    bool enable_factcheck = true;
    
    // Output
    bool keep_original_only = false; // If true, skip AI enrichment
};

// ============================================================================
// Pipeline Stage Results
// ============================================================================

struct StageResult {
    bool success = true;
    std::string error_message;
    int32_t articles_in = 0;
    int32_t articles_out = 0;
    int64_t duration_ms = 0;
    json metadata;
};

struct PipelineResult {
    bool success = true;
    std::string error_message;
    std::vector<PipelineArticle> articles;
    std::vector<StageResult> stage_results;
    int64_t total_duration_ms = 0;
    
    json to_json() const {
        json j;
        j["success"] = success;
        j["error_message"] = error_message;
        j["total_articles"] = articles.size();
        j["total_duration_ms"] = total_duration_ms;
        j["articles"] = json::array();
        for (const auto& a : articles) j["articles"].push_back(a.to_json());
        j["stages"] = json::array();
        for (const auto& s : stage_results) j["stages"].push_back(s.metadata);
        return j;
    }
};

// ============================================================================
// News Intelligence Pipeline
// ============================================================================

struct NewsPipeline {
    PipelineConfig config;
    std::vector<std::unique_ptr<yalla::ProviderAdapter>> provider_adapters;
    
    // Core components
    std::unique_ptr<yalla::TaskScheduler> scheduler;
    std::unique_ptr<yalla::LanguageDetector> lang_detector;
    std::unique_ptr<yalla::Deduplicator> deduplicator;
    std::unique_ptr<yalla::Classifier> classifier;
    std::unique_ptr<yalla::EntityExtractor> entity_extractor;
    std::unique_ptr<yalla::EventClusterer> clusterer;
    YallaSummarizerHandle summarizer = nullptr;
    YallaTranslatorHandle translator = nullptr;
    
    // AI components (optional)
    YallaInferenceEngineHandle inference_engine = nullptr;
    YallaModelManagerHandle model_manager = nullptr;
    
    // Fact-check provider
    std::unique_ptr<yalla::ProviderAdapter> factcheck_adapter;
    
    // Callbacks
    std::function<void(const std::string& stage, int progress, const std::string& message)> progress_callback;
    std::function<void(const PipelineResult&)> completion_callback;
    
    NewsPipeline(const PipelineConfig& cfg) : config(cfg) {}
    
    ~NewsPipeline() {
        if (summarizer) yalla_summarizer_destroy(summarizer);
        if (translator) yalla_translator_destroy(translator);
        if (inference_engine) yalla_inference_engine_destroy(inference_engine);
        if (model_manager) yalla_model_manager_destroy(model_manager);
    }
    
    bool initialize() {
        // Initialize scheduler
        scheduler = std::make_unique<yalla::TaskScheduler>(4);
        
        // Initialize language detector
        lang_detector = std::make_unique<yalla::LanguageDetector>();
        
        // Initialize deduplicator
        deduplicator = std::make_unique<yalla::Deduplicator>();
        if (config.enable_dedup) {
            deduplicator->set_threshold(config.dedup_threshold);
        }
        
        // Initialize classifier
        classifier = std::make_unique<yalla::Classifier>();
        
        // Initialize entity extractor
        entity_extractor = std::make_unique<yalla::EntityExtractor>();
        
        // Initialize clusterer
        clusterer = std::make_unique<yalla::EventClusterer>();
        
        // Initialize provider adapters
        for (const auto& provider_cfg : config.providers) {
            provider_adapters.push_back(
                std::make_unique<yalla::ProviderAdapter>(provider_cfg));
        }
        
        // Initialize AI if enabled
        if (config.enable_ai) {
            model_manager = yalla_model_manager_create("./models");
            if (model_manager) {
                inference_engine = yalla_inference_engine_create(model_manager);
                if (inference_engine) {
                    bool loaded = yalla_inference_engine_load_model(
                        inference_engine, config.ai_model.c_str(), 
                        config.ai_context_size, 1);
                    if (loaded) {
                        summarizer = yalla_summarizer_create(inference_engine);
                        translator = yalla_translator_create(inference_engine);
                    }
                }
            }
        }
        
        // Initialize fact-check adapter if enabled
        if (config.enable_factcheck) {
            YallaProviderConfig fc_config{};
            fc_config.type = YALLA_PROVIDER_FACTCHECK;
            fc_config.provider_id = "factcheck";
            fc_config.api_key = ""; // Set from config
            fc_config.rate_limit_rpm = 30;
            fc_config.timeout_ms = 30000;
            factcheck_adapter = std::make_unique<yalla::ProviderAdapter>(fc_config);
        }
        
        return true;
    }
    
    PipelineResult run() {
        auto start_time = std::chrono::steady_clock::now();
        PipelineResult result;
        
        // Stage 1: Discovery
        StageResult discovery = run_discovery();
        result.stage_results.push_back(discovery);
        if (!discovery.success) {
            result.success = false;
            result.error_message = "Discovery failed: " + discovery.error_message;
            finalize_result(result, start_time);
            return result;
        }
        
        std::vector<PipelineArticle> articles = std::move(discovery.metadata["articles"].get<std::vector<PipelineArticle>>());
        
        // Stage 2: Extraction (HTML → Article)
        StageResult extraction = run_extraction(articles);
        result.stage_results.push_back(extraction);
        articles = std::move(extraction.metadata["articles"].get<std::vector<PipelineArticle>>());
        
        // Stage 3: Normalization
        StageResult normalization = run_normalization(articles);
        result.stage_results.push_back(normalization);
        articles = std::move(normalization.metadata["articles"].get<std::vector<PipelineArticle>>());
        
        // Stage 4: Language Detection
        StageResult lang_detect = run_language_detection(articles);
        result.stage_results.push_back(lang_detect);
        articles = std::move(lang_detect.metadata["articles"].get<std::vector<PipelineArticle>>());
        
        // Stage 5: Deduplication
        if (config.enable_dedup) {
            StageResult dedup = run_deduplication(articles);
            result.stage_results.push_back(dedup);
            articles = std::move(dedup.metadata["articles"].get<std::vector<PipelineArticle>>());
        }
        
        // Stage 6: Classification
        if (config.enable_classification) {
            StageResult classify = run_classification(articles);
            result.stage_results.push_back(classify);
            articles = std::move(classify.metadata["articles"].get<std::vector<PipelineArticle>>());
        }
        
        // Stage 7: Entity Extraction
        if (config.enable_entities) {
            StageResult entities = run_entity_extraction(articles);
            result.stage_results.push_back(entities);
            articles = std::move(entities.metadata["articles"].get<std::vector<PipelineArticle>>());
        }
        
        // Stage 8: Event Clustering
        if (config.enable_clustering) {
            StageResult cluster = run_clustering(articles);
            result.stage_results.push_back(cluster);
            articles = std::move(cluster.metadata["articles"].get<std::vector<PipelineArticle>>());
        }
        
        // Stage 9: AI Enrichment (Summarization + Translation)
        if (config.enable_ai && (config.enable_summarization || config.enable_translation)) {
            StageResult ai = run_ai_enrichment(articles);
            result.stage_results.push_back(ai);
            articles = std::move(ai.metadata["articles"].get<std::vector<PipelineArticle>>());
        }
        
        // Stage 10: Fact-check Verification
        if (config.enable_factcheck) {
            StageResult verify = run_factcheck_verification(articles);
            result.stage_results.push_back(verify);
            articles = std::move(verify.metadata["articles"].get<std::vector<PipelineArticle>>());
        }
        
        // Stage 11: Relevance Ranking
        StageResult rank = run_relevance_ranking(articles);
        result.stage_results.push_back(rank);
        articles = std::move(rank.metadata["articles"].get<std::vector<PipelineArticle>>());
        
        finalize_result(result, start_time);
        result.articles = std::move(articles);
        return result;
    }
    
private:
    void report_progress(const std::string& stage, int progress, const std::string& message) {
        if (progress_callback) progress_callback(stage, progress, message);
    }
    
    void finalize_result(PipelineResult& result, std::chrono::steady_clock::time_point start_time) {
        auto end_time = std::chrono::steady_clock::now();
        result.total_duration_ms = std::chrono::duration_cast<std::chrono::milliseconds>(end_time - start_time).count();
        
        if (completion_callback) completion_callback(result);
    }
    
    // ========================================================================
    // Stage Implementations
    // ========================================================================
    
    StageResult run_discovery() {
        StageResult result;
        auto start = std::chrono::steady_clock::now();
        report_progress("discovery", 0, "Fetching articles from providers...");
        
        std::vector<PipelineArticle> articles;
        int total_providers = provider_adapters.size();
        
        for (int i = 0; i < total_providers; ++i) {
            int progress = (i * 100) / total_providers;
            report_progress("discovery", progress, "Fetching from provider " + std::to_string(i + 1) + "/" + std::to_string(total_providers));
            
            auto& adapter = provider_adapters[i];
            auto provider_articles = adapter->fetch_latest(config.max_articles_per_provider);
            
            for (const auto& pa : provider_articles) {
                PipelineArticle article;
                article.url = pa.url;
                article.title = pa.title;
                article.summary = pa.summary;
                article.content = pa.content;
                article.image_url = pa.image_url;
                article.category = pa.category;
                article.sentiment = pa.sentiment;
                if (pa.keywords) {
                    std::string kw(pa.keywords);
                    std::stringstream ss(kw);
                    std::string k;
                    while (std::getline(ss, k, ',')) if (!k.empty()) article.keywords.push_back(k);
                }
                article.language = pa.language;
                article.publish_date = pa.publish_date;
                article.author = pa.author;
                article.source_url = pa.source_url;
                article.provider_id = pa.provider_id;
                article.provider_name = pa.provider_name;
                article.license = pa.license;
                article.attribution_url = pa.attribution_url;
                article.raw_provider_data = pa.raw_provider_data ? json::parse(pa.raw_provider_data) : json{};
                
                articles.push_back(std::move(article));
            }
        }
        
        // Also fetch from RSS feeds if configured
        // (RSS provider handles this internally)
        
        result.articles_in = 0;
        result.articles_out = articles.size();
        result.duration_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::steady_clock::now() - start).count();
        result.metadata["articles"] = json::array();
        for (const auto& a : articles) result.metadata["articles"].push_back(a.to_json());
        result.success = true;
        report_progress("discovery", 100, "Discovered " + std::to_string(articles.size()) + " articles");
        return result;
    }
    
    StageResult run_extraction(std::vector<PipelineArticle>& articles) {
        StageResult result;
        auto start = std::chrono::steady_clock::now();
        report_progress("extraction", 0, "Extracting full article content...");
        
        // For articles that only have URL (from RSS), extract full content
        // This would use the NewsIngestion module's HTML extraction
        // For now, we assume articles from providers already have content
        
        int processed = 0;
        for (auto& article : articles) {
            if (article.content.empty() && !article.url.empty()) {
                // Would call yalla_news_ingestion_extract_html here
                // For now, use summary as content fallback
                article.content = article.summary;
            }
            processed++;
            if (processed % 10 == 0) {
                report_progress("extraction", (processed * 100) / articles.size(), 
                    "Extracted " + std::to_string(processed) + "/" + std::to_string(articles.size()));
            }
        }
        
        result.articles_in = articles.size();
        result.articles_out = articles.size();
        result.duration_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::steady_clock::now() - start).count();
        result.metadata["articles"] = json::array();
        for (const auto& a : articles) result.metadata["articles"].push_back(a.to_json());
        result.success = true;
        report_progress("extraction", 100, "Extraction complete");
        return result;
    }
    
    StageResult run_normalization(std::vector<PipelineArticle>& articles) {
        StageResult result;
        auto start = std::chrono::steady_clock::now();
        report_progress("normalization", 0, "Normalizing text...");
        
        for (size_t i = 0; i < articles.size(); ++i) {
            auto& article = articles[i];
            if (lang_detector) {
                article.normalized_title = lang_detector->normalize(
                    string_to_yalla_lang(article.language), article.title);
                article.normalized_content = lang_detector->normalize(
                    string_to_yalla_lang(article.language), article.content);
            } else {
                article.normalized_title = article.title;
                article.normalized_content = article.content;
            }
            
            if (i % 20 == 0) {
                report_progress("normalization", (i * 100) / articles.size(), 
                    "Normalized " + std::to_string(i) + "/" + std::to_string(articles.size()));
            }
        }
        
        result.articles_in = articles.size();
        result.articles_out = articles.size();
        result.duration_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::steady_clock::now() - start).count();
        result.metadata["articles"] = json::array();
        for (const auto& a : articles) result.metadata["articles"].push_back(a.to_json());
        result.success = true;
        report_progress("normalization", 100, "Normalization complete");
        return result;
    }
    
    StageResult run_language_detection(std::vector<PipelineArticle>& articles) {
        StageResult result;
        auto start = std::chrono::steady_clock::now();
        report_progress("language_detection", 0, "Detecting languages...");
        
        for (size_t i = 0; i < articles.size(); ++i) {
            auto& article = articles[i];
                if (lang_detector && article.language.empty()) {
                    float confidence = 0;
                    auto lang_result = lang_detector->detect(article.title + " " + article.content);
                    article.language = yalla_lang_to_string(lang_result.first);
                    confidence = lang_result.second;
                }
            
            if (i % 20 == 0) {
                report_progress("language_detection", (i * 100) / articles.size(),
                    "Detected " + std::to_string(i) + "/" + std::to_string(articles.size()));
            }
        }
        
        result.articles_in = articles.size();
        result.articles_out = articles.size();
        result.duration_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::steady_clock::now() - start).count();
        result.metadata["articles"] = json::array();
        for (const auto& a : articles) result.metadata["articles"].push_back(a.to_json());
        result.success = true;
        report_progress("language_detection", 100, "Language detection complete");
        return result;
    }
    
    StageResult run_deduplication(std::vector<PipelineArticle>& articles) {
        StageResult result;
        auto start = std::chrono::steady_clock::now();
        report_progress("deduplication", 0, "Checking for duplicates...");
        
        std::vector<PipelineArticle> unique_articles;
        unique_articles.reserve(articles.size());
        
        for (size_t i = 0; i < articles.size(); ++i) {
            auto& article = articles[i];
            
            // Convert to YallaArticle for deduplicator
            YallaArticle yalla_art{};
            yalla_art.url = article.url.c_str();
            yalla_art.title = article.normalized_title.empty() ? article.title.c_str() : article.normalized_title.c_str();
            yalla_art.content = article.normalized_content.empty() ? article.content.c_str() : article.normalized_content.c_str();
            
            float similarity = 0;
            bool is_dup = deduplicator->is_duplicate(&yalla_art, &similarity);
            
            article.is_duplicate = is_dup;
            article.duplicate_similarity = similarity;
            
            if (!is_dup) {
                deduplicator->add(&yalla_art);
                unique_articles.push_back(std::move(article));
            }
            
            if (i % 20 == 0) {
                report_progress("deduplication", (i * 100) / articles.size(),
                    "Checked " + std::to_string(i) + "/" + std::to_string(articles.size()));
            }
        }
        
        result.articles_in = articles.size();
        result.articles_out = unique_articles.size();
        result.duration_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::steady_clock::now() - start).count();
        result.metadata["articles"] = json::array();
        for (const auto& a : unique_articles) result.metadata["articles"].push_back(a.to_json());
        result.success = true;
        report_progress("deduplication", 100, 
            "Removed " + std::to_string(articles.size() - unique_articles.size()) + " duplicates");
        
        articles = std::move(unique_articles);
        return result;
    }
    
    StageResult run_classification(std::vector<PipelineArticle>& articles) {
        StageResult result;
        auto start = std::chrono::steady_clock::now();
        report_progress("classification", 0, "Classifying articles...");
        
        for (size_t i = 0; i < articles.size(); ++i) {
            auto& article = articles[i];
            
            auto [category, confidence] = classifier->classify(
                article.title, article.content, article.summary);
            article.category = category;
            article.sentiment = confidence;
            
            std::string subcategory = classifier->get_subcategory(
                article.title, article.content, article.summary);
            article.subcategory = subcategory;
            
            if (i % 20 == 0) {
                report_progress("classification", (i * 100) / articles.size(),
                    "Classified " + std::to_string(i) + "/" + std::to_string(articles.size()));
            }
        }
        
        result.articles_in = articles.size();
        result.articles_out = articles.size();
        result.duration_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::steady_clock::now() - start).count();
        result.metadata["articles"] = json::array();
        for (const auto& a : articles) result.metadata["articles"].push_back(a.to_json());
        result.success = true;
        report_progress("classification", 100, "Classification complete");
        return result;
    }
    
    StageResult run_entity_extraction(std::vector<PipelineArticle>& articles) {
        StageResult result;
        auto start = std::chrono::steady_clock::now();
        report_progress("entity_extraction", 0, "Extracting entities...");
        
        for (size_t i = 0; i < articles.size(); ++i) {
            auto& article = articles[i];
            
            auto entities = entity_extractor->extract(
                article.title, article.content, article.language);
            
            article.entities.clear();
            for (const auto& e : entities) {
                article.entities.push_back(e);
            }
            
            // Extract keywords from entities + content
            article.keywords.clear();
            for (const auto& e : article.entities) {
                if (e.canonical) article.keywords.push_back(e.canonical);
            }
            
            if (i % 20 == 0) {
                report_progress("entity_extraction", (i * 100) / articles.size(),
                    "Extracted entities from " + std::to_string(i) + "/" + std::to_string(articles.size()));
            }
        }
        
        result.articles_in = articles.size();
        result.articles_out = articles.size();
        result.duration_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::steady_clock::now() - start).count();
        result.metadata["articles"] = json::array();
        for (const auto& a : articles) result.metadata["articles"].push_back(a.to_json());
        result.success = true;
        report_progress("entity_extraction", 100, "Entity extraction complete");
        return result;
    }
    
    StageResult run_clustering(std::vector<PipelineArticle>& articles) {
        StageResult result;
        auto start = std::chrono::steady_clock::now();
        report_progress("clustering", 0, "Clustering articles into events...");
        
        if (articles.size() < 2) {
            result.articles_in = articles.size();
            result.articles_out = articles.size();
            result.duration_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                std::chrono::steady_clock::now() - start).count();
            result.metadata["articles"] = json::array();
            for (const auto& a : articles) result.metadata["articles"].push_back(a.to_json());
            result.success = true;
            report_progress("clustering", 100, "Not enough articles for clustering");
            return result;
        }
        
        // Convert to YallaArticle array
        std::vector<YallaArticle> yalla_articles;
        yalla_articles.reserve(articles.size());
        for (const auto& a : articles) {
            YallaArticle ya{};
            ya.url = a.url.c_str();
            ya.title = a.title.c_str();
            ya.content = a.content.c_str();
            ya.summary = a.summary.c_str();
            ya.category = a.category.c_str();
            ya.keywords = join_keywords(a.keywords).c_str();
            ya.language = a.language.c_str();
            ya.sentiment = a.sentiment;
            yalla_articles.push_back(ya);
        }
        
        auto clusters = clusterer->cluster_ex(
            yalla_articles, config.cluster_algorithm, 0, config.cluster_eps, config.cluster_min_samples);
        int32_t cluster_count = static_cast<int32_t>(clusters.size());
        
        // Map cluster IDs back to articles
        std::unordered_map<std::string, int32_t> url_to_cluster;
        for (int c = 0; c < cluster_count; ++c) {
            for (int ai = 0; ai < clusters[c].article_count; ++ai) {
                if (clusters[c].article_urls[ai]) {
                    url_to_cluster[clusters[c].article_urls[ai]] = c;
                }
            }
        }
        
        for (auto& article : articles) {
            auto it = url_to_cluster.find(article.url);
            if (it != url_to_cluster.end()) {
                article.cluster_id = it->second;
            }
        }
        
        result.articles_in = articles.size();
        result.articles_out = articles.size();
        result.duration_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::steady_clock::now() - start).count();
        result.metadata["articles"] = json::array();
        for (const auto& a : articles) result.metadata["articles"].push_back(a.to_json());
        result.metadata["clusters"] = cluster_count;
        result.success = true;
        report_progress("clustering", 100, "Created " + std::to_string(cluster_count) + " event clusters");
        return result;
    }
    
    StageResult run_ai_enrichment(std::vector<PipelineArticle>& articles) {
        StageResult result;
        auto start = std::chrono::steady_clock::now();
        report_progress("ai_enrichment", 0, "Running AI summarization and translation...");
        
        if (!summarizer && !translator) {
            result.articles_in = articles.size();
            result.articles_out = articles.size();
            result.duration_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                std::chrono::steady_clock::now() - start).count();
            result.metadata["articles"] = json::array();
            for (const auto& a : articles) result.metadata["articles"].push_back(a.to_json());
            result.success = false;
            result.error_message = "AI not initialized";
            report_progress("ai_enrichment", 100, "AI not available");
            return result;
        }
        
        for (size_t i = 0; i < articles.size(); ++i) {
            auto& article = articles[i];
            
            // Summarization
            if (config.enable_summarization && summarizer && !article.content.empty()) {
                const char* summary = yalla_summarizer_summarize(
                    summarizer, article.title.c_str(), article.content.c_str(),
                    article.language.c_str(), config.summary_max_length);
                article.ai_summary = summary ? summary : "";
                if (summary) yalla_free_string(summary);
            }
            
            // Translation
            if (config.enable_translation && translator && !article.content.empty()) {
                auto source_lang = string_to_yalla_lang(article.language);
                for (const auto& target_lang_code : config.target_languages) {
                    if (target_lang_code == article.language) continue;
                    auto target_lang = string_to_yalla_lang(target_lang_code);
                    const char* translated = yalla_translator_translate(
                        translator, article.content.c_str(), source_lang, target_lang);
                    if (translated) {
                        article.translations[target_lang_code] = translated;
                        yalla_free_string(translated);
                    }
                }
            }
            
            if (i % 10 == 0) {
                report_progress("ai_enrichment", (i * 100) / articles.size(),
                    "AI enriched " + std::to_string(i) + "/" + std::to_string(articles.size()));
            }
        }
        
        result.articles_in = articles.size();
        result.articles_out = articles.size();
        result.duration_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::steady_clock::now() - start).count();
        result.metadata["articles"] = json::array();
        for (const auto& a : articles) result.metadata["articles"].push_back(a.to_json());
        result.success = true;
        report_progress("ai_enrichment", 100, "AI enrichment complete");
        return result;
    }
    
    StageResult run_factcheck_verification(std::vector<PipelineArticle>& articles) {
        StageResult result;
        auto start = std::chrono::steady_clock::now();
        report_progress("factcheck", 0, "Verifying claims with fact-check sources...");
        
        if (!factcheck_adapter) {
            result.articles_in = articles.size();
            result.articles_out = articles.size();
            result.duration_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                std::chrono::steady_clock::now() - start).count();
            result.metadata["articles"] = json::array();
            for (const auto& a : articles) result.metadata["articles"].push_back(a.to_json());
            result.success = false;
            result.error_message = "Fact-check adapter not initialized";
            report_progress("factcheck", 100, "Fact-check not available");
            return result;
        }
        
        for (size_t i = 0; i < articles.size(); ++i) {
            auto& article = articles[i];
            
            // Search for fact-checks related to this article's key claims
            std::string query = article.title + " " + join_keywords(article.keywords);
            auto factchecks = factcheck_adapter->fetch(query, 5);
            
            if (!factchecks.empty()) {
                article.verified = true;
                article.verification_source = "Google Fact Check Tools";
                // Could store fact-check details in raw_provider_data
            }
            
            if (i % 10 == 0) {
                report_progress("factcheck", (i * 100) / articles.size(),
                    "Verified " + std::to_string(i) + "/" + std::to_string(articles.size()));
            }
        }
        
        result.articles_in = articles.size();
        result.articles_out = articles.size();
        result.duration_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::steady_clock::now() - start).count();
        result.metadata["articles"] = json::array();
        for (const auto& a : articles) result.metadata["articles"].push_back(a.to_json());
        result.success = true;
        report_progress("factcheck", 100, "Fact-check verification complete");
        return result;
    }
    
    StageResult run_relevance_ranking(std::vector<PipelineArticle>& articles) {
        StageResult result;
        auto start = std::chrono::steady_clock::now();
        report_progress("ranking", 0, "Ranking articles by relevance...");
        
        // Simple relevance scoring based on:
        // - Recency (newer = higher)
        // - Source credibility (known providers = higher)
        // - Content length (substantive = higher)
        // - Cluster membership (clustered = higher)
        // - AI summary availability (enriched = higher)
        
        auto now_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::system_clock::now().time_since_epoch()).count();
        
        for (auto& article : articles) {
            float score = 0.5f; // Base
            
            // Recency (within last 24h = +0.2, last week = +0.1)
            int64_t age_hours = (now_ms - article.publish_date) / (1000 * 60 * 60);
            if (age_hours < 24) score += 0.2f;
            else if (age_hours < 168) score += 0.1f;
            
            // Source credibility
            static const std::set<std::string> premium_sources = {
                "reuters", "ap", "bbc", "nytimes", "washingtonpost", "aljazeera", "france24"
            };
            std::string source_lower = article.provider_name;
            std::transform(source_lower.begin(), source_lower.end(), source_lower.begin(), ::tolower);
            if (premium_sources.count(source_lower)) score += 0.15f;
            
            // Content quality
            if (article.content.length() > 500) score += 0.1f;
            if (article.content.length() > 2000) score += 0.05f;
            
            // Cluster membership
            if (article.cluster_id >= 0) score += 0.1f;
            
            // AI enrichment
            if (!article.ai_summary.empty()) score += 0.1f;
            if (!article.translations.empty()) score += 0.05f;
            
            // Verification
            if (article.verified) score += 0.1f;
            
            // Penalize duplicates
            if (article.is_duplicate) score -= 0.3f;
            
            article.relevance_score = std::clamp(score, 0.0f, 1.0f);
        }
        
        // Sort by relevance (descending)
        std::sort(articles.begin(), articles.end(),
            [](const PipelineArticle& a, const PipelineArticle& b) {
                return a.relevance_score > b.relevance_score;
            });
        
        result.articles_in = articles.size();
        result.articles_out = articles.size();
        result.duration_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::steady_clock::now() - start).count();
        result.metadata["articles"] = json::array();
        for (const auto& a : articles) result.metadata["articles"].push_back(a.to_json());
        result.success = true;
        report_progress("ranking", 100, "Ranking complete");
        return result;
    }
    
    // Helper functions
    static YallaLanguage string_to_yalla_lang(const std::string& lang) {
        if (lang == "ar" || lang == "arabic") return YALLA_LANG_ARABIC;
        if (lang == "fr" || lang == "french") return YALLA_LANG_FRENCH;
        return YALLA_LANG_ENGLISH;
    }
    
    static std::string yalla_lang_to_string(YallaLanguage lang) {
        switch (lang) {
            case YALLA_LANG_ARABIC: return "ar";
            case YALLA_LANG_FRENCH: return "fr";
            case YALLA_LANG_ENGLISH: return "en";
            default: return "en";
        }
    }
    
    static std::string join_keywords(const std::vector<std::string>& keywords) {
        std::string result;
        for (size_t i = 0; i < keywords.size(); ++i) {
            if (i > 0) result += ",";
            result += keywords[i];
        }
        return result;
    }
};

// ============================================================================
// C API for Pipeline
// ============================================================================

typedef struct NewsPipeline* NewsPipelineHandle;

extern "C" {

YALLA_CORE_EXPORT NewsPipelineHandle yalla_pipeline_create(const char* config_json) {
    if (!config_json) return nullptr;
    
    try {
        auto config = json::parse(config_json);
        
        PipelineConfig cfg;
        // Parse config from JSON (simplified)
        cfg.enable_ai = config.value("enable_ai", true);
        cfg.ai_model = config.value("ai_model", "qwen3-0.6b-q4");
        cfg.enable_summarization = config.value("enable_summarization", true);
        cfg.summary_max_length = config.value("summary_max_length", 150);
        cfg.enable_translation = config.value("enable_translation", true);
        cfg.target_languages = config.value("target_languages", std::vector<std::string>{"ar", "en", "fr"});
        cfg.enable_dedup = config.value("enable_dedup", true);
        cfg.dedup_threshold = config.value("dedup_threshold", 0.85f);
        cfg.enable_classification = config.value("enable_classification", true);
        cfg.enable_entities = config.value("enable_entities", true);
        cfg.enable_clustering = config.value("enable_clustering", true);
        cfg.cluster_algorithm = config.value("cluster_algorithm", 1);
        cfg.cluster_eps = config.value("cluster_eps", 0.5);
        cfg.cluster_min_samples = config.value("cluster_min_samples", 2);
        cfg.max_articles_per_provider = config.value("max_articles_per_provider", 50);
        cfg.enable_factcheck = config.value("enable_factcheck", true);
        
        // Parse providers
        if (config.contains("providers") && config["providers"].is_array()) {
            for (const auto& p : config["providers"]) {
                YallaProviderConfig pc{};
                pc.type = static_cast<YallaProviderType>(p.value("type", 0));
                pc.provider_id = strdup(p.value("provider_id", "").c_str());
                pc.api_key = strdup(p.value("api_key", "").c_str());
                pc.base_url = strdup(p.value("base_url", "").c_str());
                pc.timeout_ms = p.value("timeout_ms", 30000);
                pc.rate_limit_rpm = p.value("rate_limit_rpm", 60);
                pc.max_retries = p.value("max_retries", 3);
                pc.custom_params = strdup(p.value("custom_params", "{}").c_str());
                cfg.providers.push_back(pc);
            }
        }
        
        auto* pipeline = new NewsPipeline(cfg);
        if (!pipeline->initialize()) {
            delete pipeline;
            return nullptr;
        }
        return reinterpret_cast<NewsPipelineHandle>(pipeline);
    } catch (...) {
        return nullptr;
    }
}

YALLA_CORE_EXPORT void yalla_pipeline_destroy(NewsPipelineHandle handle) {
    if (handle) delete reinterpret_cast<NewsPipeline*>(handle);
}

YALLA_CORE_EXPORT const char* yalla_pipeline_run(NewsPipelineHandle handle) {
    if (!handle) return strdup("{\"success\":false,\"error\":\"Invalid pipeline handle\"}");
    
    auto* pipeline = reinterpret_cast<NewsPipeline*>(handle);
    PipelineResult result = pipeline->run();
    
    std::string json_str = result.to_json().dump();
    return strdup(json_str.c_str());
}

YALLA_CORE_EXPORT void yalla_pipeline_set_progress_callback(NewsPipelineHandle handle,
    void (*callback)(const char* stage, int32_t progress, const char* message)) {
    if (!handle) return;
    auto* pipeline = reinterpret_cast<NewsPipeline*>(handle);
    pipeline->progress_callback = [callback](const std::string& stage, int progress, const std::string& message) {
        callback(stage.c_str(), progress, message.c_str());
    };
}

YALLA_CORE_EXPORT void yalla_pipeline_set_completion_callback(NewsPipelineHandle handle,
    void (*callback)(const char* result_json)) {
    if (!handle) return;
    auto* pipeline = reinterpret_cast<NewsPipeline*>(handle);
    pipeline->completion_callback = [callback](const PipelineResult& result) {
        callback(result.to_json().dump().c_str());
    };
}

} // extern "C"