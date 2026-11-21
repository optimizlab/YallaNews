#ifndef YALLA_EDITORIAL_QUALITY_H
#define YALLA_EDITORIAL_QUALITY_H

#include "core/job_context.h"

#include <string>

namespace yalla {

struct QualityReport {
    bool clear = true;
    bool coherent = true;
    bool grammar_ok = true;
    bool headline_accurate = true;
    bool attribution_ok = true;
    bool language_consistent = true;
    bool unsupported_statements = false;
    std::vector<std::string> findings;
    double score = 1.0;  // tied to documented checks, not an arbitrary percentage
};

// EditorialQualityEngine evaluates clarity, coherence, grammar, readability,
// headline accuracy, introduction quality, repetition, structure, attribution,
// language consistency, completeness and unsupported statements.
class EditorialQualityEngine {
public:
    explicit EditorialQualityEngine(JobContext& job);

    QualityReport evaluate(const std::string& article,
                           const std::string& headline,
                           const std::string& language) const;

private:
    JobContext& job_;
};

} // namespace yalla

#endif // YALLA_EDITORIAL_QUALITY_H
