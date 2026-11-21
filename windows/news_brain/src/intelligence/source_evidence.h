#ifndef YALLA_SOURCE_EVIDENCE_H
#define YALLA_SOURCE_EVIDENCE_H

#include "core/job_context.h"
#include "input/input_adapter.h"
#include "yalla_editorial.h"

#include <string>
#include <vector>

namespace yalla {

// SourceEvidenceEngine assigns temporary source ids and builds evidence records
// referencing source, URL, publisher, date, passage, offsets, language and
// attribution. It never claims independent confirmation for syndicated material.
class SourceEvidenceEngine {
public:
    explicit SourceEvidenceEngine(JobContext& job);

    std::vector<Evidence> build_evidence(const NormalizedSource& source,
                                         int32_t source_index) const;

private:
    JobContext& job_;
    mutable int32_t source_counter_ = 0;
};

} // namespace yalla

#endif // YALLA_SOURCE_EVIDENCE_H
