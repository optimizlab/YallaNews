#include "deterministic_writer.h"
#include "editorial/news_writer.h"

namespace yalla {

DeterministicWriter::DeterministicWriter(JobContext& job) : job_(job) {}

BackendCapabilities DeterministicWriter::capabilities() const {
    BackendCapabilities cap;
    cap.supports_arabic = true;
    cap.supports_french = true;
    cap.supports_english = true;
    cap.supports_streaming = false;
    cap.max_output_bytes = 32 * 1024;
    cap.deterministic = true;
    return cap;
}

Status DeterministicWriter::generate(const GenerationRequest& request,
                                      GenerationResult& result) {
    if (job_.is_cancelled()) return Status::CANCELLED;
    if (!request.plan || !request.facts) return Status::INVALID_ARGUMENT;

    NewsWriter writer(job_);
    GenerationOptions opts;
    if (request.options) opts = *request.options;

    result = writer.write(*request.plan, *request.facts,
                          request.evidence ? *request.evidence : std::vector<Evidence>{},
                          std::vector<Entity>{}, EventRepresentation{}, opts);
    return result.status;
}

} // namespace yalla
