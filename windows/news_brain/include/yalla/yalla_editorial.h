#ifndef YALLA_EDITORIAL_H
#define YALLA_EDITORIAL_H

#include "yalla_errors.h"
#include "yalla_generation_backend.h"

#include <cstdint>
#include <memory>
#include <string>
#include <utility>
#include <vector>

namespace yalla {

// A single extracted fact with full provenance.
struct Fact {
    std::string id;
    std::string subject;
    std::string predicate;
    std::string object;
    std::string fact_type;          // confirmed | attributed | allegation | opinion | estimate | unknown
    std::string source_id;
    size_t passage_offset = 0;
    size_t passage_length = 0;
    std::string original_language;
    std::string extraction_method;
    double confidence = 0.0;
    bool verified = false;
};

// A named entity with original spelling and canonical form.
struct Entity {
    std::string id;
    std::string name;
    std::string canonical;
    std::string type;               // person | organization | location | ...
    std::string original_language;
    double confidence = 0.0;
};

// A piece of source evidence referenced by facts.
struct Evidence {
    std::string source_id;
    std::string url;
    std::string publisher;
    int64_t published_at = 0;
    std::string passage;
    size_t passage_offset = 0;
    size_t passage_length = 0;
    std::string source_language;
    std::string attribution;
    bool independent = false;       // true only when source independence is established
};

// Temporary event representation for a single job.
struct EventRepresentation {
    std::string id;
    std::string type;               // new | update | reaction | historical | opinion | unrelated
    std::string summary;
    double confidence = 0.0;
};

// Editorial plan produced before writing.
struct EditorialPlan {
    std::string article_type;       // breaking_news | general_news | government_announcement | ...
    std::string angle;
    std::string main_message;
    std::string target_audience;
    std::string target_language;
    std::string headline_direction;
    std::string introduction_objective;
    std::string conclusion_objective;
    int32_t target_length = 0;
    std::vector<std::string> body_sections;
    std::vector<std::string> supporting_facts_per_section;
    std::vector<std::string> necessary_attributions;
    std::vector<std::string> uncertainties;
    double confidence = 0.0;
};

// Options controlling article generation.
struct GenerationOptions {
    std::string language;
    int32_t max_length = 0;
    std::string style;              // professional | concise | detailed
    bool require_attribution = true;
};

// Result of generation: the composed article text plus metadata.
struct GenerationResult {
    Status status = Status::OK;
    std::string headline;
    std::string subtitle;
    std::string introduction;
    std::vector<std::pair<std::string, std::string>> body; // heading, text
    std::string conclusion;
    std::string language;
    std::string article_type;
    std::string error_message;
};

// Token used to request cooperative cancellation.
struct CancellationToken {
    bool* cancelled = nullptr;
    bool is_cancelled() const { return cancelled != nullptr && *cancelled; }
};

} // namespace yalla

#endif // YALLA_EDITORIAL_H
