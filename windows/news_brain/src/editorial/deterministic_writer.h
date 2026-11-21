#ifndef YALLA_DETERMINISTIC_WRITER_H
#define YALLA_DETERMINISTIC_WRITER_H

#include "core/job_context.h"
#include "yalla_generation_backend.h"

namespace yalla {

// DeterministicWriter runs inside the strict 16 MiB core using fact ordering,
// editorial templates, rule-based transitions and controlled vocabulary.
// Functional fallback, not human-level creative writing.
class DeterministicWriter : public IGenerationBackend {
public:
    explicit DeterministicWriter(JobContext& job);

    BackendCapabilities capabilities() const override;
    Status generate(const GenerationRequest& request, GenerationResult& result) override;

private:
    JobContext& job_;
};

} // namespace yalla

#endif // YALLA_DETERMINISTIC_WRITER_H
