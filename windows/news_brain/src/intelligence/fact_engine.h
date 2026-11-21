#ifndef YALLA_FACT_ENGINE_H
#define YALLA_FACT_ENGINE_H

#include "core/job_context.h"
#include "intelligence/content_understanding.h"
#include "yalla_editorial.h"

#include <string>
#include <vector>

namespace yalla {

// FactEngine turns extracted understanding into sourced facts. Every fact has a
// unique job-local id, subject, predicate, object, type, source, offsets,
// original language, extraction method and confidence. Allegations are never
// converted into established facts.
class FactEngine {
public:
    explicit FactEngine(JobContext& job);

    // Convert understanding + evidence into a bounded fact sheet.
    std::vector<Fact> extract_facts(const UnderstandingResult& understanding,
                                    const std::vector<Evidence>& evidence,
                                    const std::string& default_language) const;

    int32_t next_fact_id();

private:
    JobContext& job_;
    mutable int32_t fact_counter_ = 0;
};

} // namespace yalla

#endif // YALLA_FACT_ENGINE_H
