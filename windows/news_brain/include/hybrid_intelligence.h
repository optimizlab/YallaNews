#ifndef NEWSBRAIN_HYBRID_INTELLIGENCE_H
#define NEWSBRAIN_HYBRID_INTELLIGENCE_H

#include "yalla/yalla_brain.h"
#include <cstdint>
#include <cstddef>
#include <string>
#include <vector>
#include <map>
#include <memory>
#include <chrono>
#include <functional>

namespace newsbrain {

// ============================================================================
// DECISION OUTCOMES (spec section 14)
// ============================================================================
enum class NewsDecision {
    UNKNOWN = 0,
    ACCEPT = 1,              // Strong evidence of reportable news
    REVIEW = 2,              // Potentially useful but ambiguous/incomplete
    REJECT = 3,              // Non-news, SEO, promotional, irrelevant pages, empty content, or duplicate content without a meaningful update
    NEW_DEVELOPMENT = 4      // Known event with genuinely new information
};

inline const char* decisionToString(NewsDecision d) {
    switch (d) {
        case NewsDecision::ACCEPT: return "ACCEPT";
        case NewsDecision::REVIEW: return "REVIEW";
        case NewsDecision::REJECT: return "REJECT";
        case NewsDecision::NEW_DEVELOPMENT: return "NEW_DEVELOPMENT";
        default: return "UNKNOWN";
    }
}

// ============================================================================
// NEWS SCORES (spec section 13)
// ============================================================================
struct NewsScores {
    double news_signal_score = 0.0;           // Is this real news?
    double article_quality_score = 0.0;       // Writing quality
    double event_specificity_score = 0.0;     // How specific is the event?
    double title_body_match_score = 0.0;      // Headline supported by body?
    double semantic_confidence = 0.0;         // TinyLLM confidence
    double freshness_score = 0.0;             // How recent?
    double category_confidence = 0.0;         // Classification confidence
    double duplicate_probability = 0.0;       // Is this a dup?
    double importance_score = 0.0;            // News value
    double extraction_confidence = 0.0;       // Extraction reliability

    double overallScore() const {
        double w[] = {0.20, 0.15, 0.15, 0.10, 0.10, 0.10, 0.05, 0.05, 0.05, 0.05};
        double vals[] = {
            news_signal_score, article_quality_score, event_specificity_score,
            title_body_match_score, semantic_confidence, freshness_score,
            category_confidence, 1.0 - duplicate_probability, importance_score,
            extraction_confidence
        };
        double sum = 0.0;
        for (int i = 0; i < 10; ++i) sum += w[i] * vals[i];
        return sum;
    }
};

// ============================================================================
// EVENT REPRESENTATION (spec section 7)
// ============================================================================
struct DetectedEvent {
    std::string event_id;
    std::string action;              // "announced", "launched", "resigned", etc.
    std::string subject;             // Who/what acted
    std::string object;              // Target of action
    std::vector<std::string> people;
    std::vector<std::string> organizations;
    std::vector<std::string> locations;
    std::string country;
    std::string event_date;          // When event happened
    std::string publication_date;    // When reported
    std::vector<std::string> numbers;
    std::string outcome;
    std::string reported_cause;
    std::string consequences;
    std::string new_development;     // What's new vs prior knowledge
    bool is_new_development = false;
    double confidence = 0.0;
    std::vector<std::string> evidence_passages;
    std::vector<size_t> evidence_offsets;
};

// ============================================================================
// CATEGORY CLASSIFICATION (spec section 9)
// ============================================================================
enum class NewsCategory {
    UNKNOWN = 0,
    POLITICS,
    ECONOMY,
    SPORT,
    TECH,
    SCIENCE,
    HEALTH,
    SOCIETY,
    FACTS,
    WORLD,
    CULTURE,
    ARTS,
    ISLAMIC,
    WOMEN,
    VARIETIES
};

inline const char* categoryToString(NewsCategory c) {
    switch (c) {
        case NewsCategory::POLITICS: return "POLITICS";
        case NewsCategory::ECONOMY: return "ECONOMY";
        case NewsCategory::SPORT: return "SPORT";
        case NewsCategory::TECH: return "TECH";
        case NewsCategory::SCIENCE: return "SCIENCE";
        case NewsCategory::HEALTH: return "HEALTH";
        case NewsCategory::SOCIETY: return "SOCIETY";
        case NewsCategory::FACTS: return "FACTS";
        case NewsCategory::WORLD: return "WORLD";
        case NewsCategory::CULTURE: return "CULTURE";
        case NewsCategory::ARTS: return "ARTS";
        case NewsCategory::ISLAMIC: return "ISLAMIC";
        case NewsCategory::WOMEN: return "WOMEN";
        case NewsCategory::VARIETIES: return "VARIETIES";
        default: return "UNKNOWN";
    }
}

struct CategoryResult {
    NewsCategory primary = NewsCategory::UNKNOWN;
    NewsCategory secondary = NewsCategory::UNKNOWN;
    double primary_confidence = 0.0;
    double secondary_confidence = 0.0;
    std::vector<std::string> matched_keywords;
    std::string reasoning;
};

// ============================================================================
// HEADLINE INTELLIGENCE (spec section 8)
// ============================================================================
struct HeadlineAnalysis {
    bool is_factual = true;
    bool is_sensational = false;
    bool is_clickbait = false;
    bool is_question = false;
    bool is_opinion = false;
    bool is_prediction = false;
    bool has_exaggeration = false;
    bool has_missing_context = false;
    bool title_body_mismatch = false;
    bool old_event_as_new = false;
    double sensationalism_score = 0.0;
    double clickbait_score = 0.0;
    std::vector<std::string> issues;
    std::vector<std::string> warnings;
};

// ============================================================================
// DUPLICATE DETECTION (spec section 11)
// ============================================================================
struct DuplicateResult {
    bool is_duplicate = false;
    bool is_near_duplicate = false;
    bool is_syndicated = false;
    bool is_rewrite = false;
    bool has_new_development = false;
    double similarity_score = 0.0;
    std::string duplicate_of_id;     // Source article ID
    std::vector<std::string> duplicate_reasons;
    std::string cluster_id;          // Event cluster
};

// ============================================================================
// VALIDATION RESULT (spec section 4)
// ============================================================================
struct NewsValidationResult {
    bool is_real_news = false;       // Passes all real-news checks
    bool has_event_evidence = false; // Concrete event detected
    bool content_quality_ok = false; // Body is substantive
    bool extraction_ok = false;      // Could extract article body
    bool language_ok = false;        // Supported language
    std::vector<std::string> rejection_reasons;
    std::vector<std::string> warnings;
    double overall_confidence = 0.0;
};

// ============================================================================
// MAIN HYBRID INTELLIGENCE RESULT
// ============================================================================
struct HybridIntelligenceResult {
    NewsDecision decision = NewsDecision::UNKNOWN;
    NewsScores scores;
    DetectedEvent event;
    CategoryResult category;
    HeadlineAnalysis headline;
    DuplicateResult duplicate;
    NewsValidationResult validation;
    std::string explainability;      // Human-readable explanation (spec 17)
    std::string knowledge_version;   // Knowledge base version used
    int tiny_llm_invoked = 0;        // How many times TinyLLM was called
    double processing_time_ms = 0.0;
    std::vector<std::string> pipeline_trace; // Step-by-step trace
};

// ============================================================================
// CONFIGURATION
// ============================================================================
struct HybridIntelligenceConfig {
    bool enable_tiny_llm = false;        // Layer B on/off
    bool enable_knowledge_base = true;   // Layer C on/off
    bool enable_duplicate_tracking = true;
    bool enable_event_clustering = true;
    bool enable_feedback_learning = false;
    double news_signal_threshold = 0.60;
    double accept_threshold = 0.75;
    double review_threshold = 0.50;
    double duplicate_threshold = 0.85;
    double near_duplicate_threshold = 0.70;
    size_t max_tiny_llm_calls_per_job = 3;
    size_t max_tiny_llm_tokens = 512;
    std::string model_path;              // TinyLLM model path
    std::string knowledge_base_path;     // Knowledge base directory
    size_t working_memory_bytes = 16 * 1024 * 1024; // 16 MiB
};

// ============================================================================
// MAIN HYBRID INTELLIGENCE ENGINE
// ============================================================================
class HybridIntelligenceEngine {
public:
    explicit HybridIntelligenceEngine(const HybridIntelligenceConfig& config);
    ~HybridIntelligenceEngine();

    HybridIntelligenceEngine(const HybridIntelligenceEngine&) = delete;
    HybridIntelligenceEngine& operator=(const HybridIntelligenceEngine&) = delete;

    // Main entry point: process a candidate article through all 7 passes
    HybridIntelligenceResult process(
        const std::string& title,
        const std::string& body,
        const std::string& summary,
        const std::string& url,
        const std::string& language,
        const std::string& source_id,
        const std::string& published_date,
        const std::vector<std::string>& prior_article_ids = {},
        const std::vector<std::string>& prior_event_ids = {}
    );

    // Get explainability for last result
    std::string getLastExplainability() const;

    // Record feedback for continuous improvement (spec 16)
    void recordFeedback(
        const std::string& article_id,
        NewsDecision original_decision,
        NewsDecision corrected_decision,
        const std::string& correction_reason
    );

    // Get knowledge base version
    std::string getKnowledgeVersion() const;

    // Check if engine is healthy
    bool isHealthy() const;

private:
    HybridIntelligenceConfig config_;
    std::string knowledge_version_;
    bool healthy_ = false;

    // Pipeline trace for explainability
    std::vector<std::string> trace_;

    // Pass functions (spec section 12)
    HybridIntelligenceResult pass1_CppPreprocessing(
        const std::string& title, const std::string& body,
        const std::string& summary, const std::string& url,
        const std::string& language
    );

    HybridIntelligenceResult pass2_PhpRules(
        HybridIntelligenceResult& result,
        const std::string& title, const std::string& body
    );

    HybridIntelligenceResult pass3_PreliminaryScore(
        HybridIntelligenceResult& result
    );

    HybridIntelligenceResult pass4_TinyLlmSemantic(
        HybridIntelligenceResult& result,
        const std::string& title, const std::string& body,
        const std::string& summary
    );

    HybridIntelligenceResult pass5_CppValidation(
        HybridIntelligenceResult& result
    );

    HybridIntelligenceResult pass6_FinalDecision(
        HybridIntelligenceResult& result
    );

    HybridIntelligenceResult pass7_StoreFeedback(
        HybridIntelligenceResult& result,
        const std::string& article_id
    );

    // Helper methods
    void addTrace(const std::string& step, const std::string& detail);
    NewsDecision makeDecision(const NewsScores& scores, const NewsValidationResult& val);
    std::string buildExplainability(const HybridIntelligenceResult& r);

    // Category classification
    CategoryResult classifyCategory(
        const std::string& title, const std::string& body
    );

    // Headline intelligence
    HeadlineAnalysis analyzeHeadline(
        const std::string& title, const std::string& body
    );

    // Importance scoring
    double computeImportance(
        const std::string& title, const std::string& body,
        const CategoryResult& cat
    );

    double computeFreshness(const std::string& pub_date);
    double computeEventSpecificity(const DetectedEvent& event);
    double computeTitleBodyMatch(
        const std::string& title, const std::string& body
    );

    // TinyLLM interface
    std::string buildTinyLlmPrompt(
        const std::string& title,
        const std::string& body,
        const std::string& summary,
        const HybridIntelligenceResult& current
    );

    std::string invokeTinyLlm(const std::string& prompt);
    void parseTinyLlmResponse(
        HybridIntelligenceResult& result, const std::string& response
    );
};

// ============================================================================
// C ABI EXPORTS (for integration with Flutter/Dart)
// ============================================================================
#ifdef __cplusplus
extern "C" {
#endif

#define NEWSBRAIN_HYBRID_EXPORT __declspec(dllexport)

// Create a hybrid intelligence engine instance
NEWSBRAIN_HYBRID_EXPORT void* newsbrain_hybrid_create(
    int enable_tiny_llm,
    const char* model_path,
    const char* knowledge_base_path,
    size_t working_memory_bytes
);

// Destroy engine instance
NEWSBRAIN_HYBRID_EXPORT void newsbrain_hybrid_destroy(void* engine);

// Process an article through hybrid intelligence
// Returns JSON string (caller must free with newsbrain_hybrid_free_string)
NEWSBRAIN_HYBRID_EXPORT const char* newsbrain_hybrid_process(
    void* engine,
    const char* title,
    const char* body,
    const char* summary,
    const char* url,
    const char* language,
    const char* source_id,
    const char* published_date
);

// Free string allocated by hybrid engine
NEWSBRAIN_HYBRID_EXPORT void newsbrain_hybrid_free_string(const char* str);

// Get version
NEWSBRAIN_HYBRID_EXPORT const char* newsbrain_hybrid_version();

// Record feedback (spec 16)
NEWSBRAIN_HYBRID_EXPORT void newsbrain_hybrid_record_feedback(
    void* engine,
    const char* article_id,
    int original_decision,
    int corrected_decision,
    const char* correction_reason
);

#ifdef __cplusplus
}
#endif

#endif // NEWSBRAIN_HYBRID_INTELLIGENCE_H
