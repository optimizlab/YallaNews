#include "brain.h"

namespace yalla {

Brain::Brain(const BrainConfig& config) : config_(config), valid_(true) {}

Brain::~Brain() = default;

Status Brain::write_article(const YallaEditorialRequest& request,
                            std::string& out_json) {
    out_json.clear();
    if (!valid_) return Status::INTERNAL_ERROR;
    // One job per instance; a fresh context per call enforces job-scoped memory.
    job_ = std::make_unique<JobContext>(config_.limits);
    if (!job_) return Status::OUT_OF_MEMORY;
    // Pipeline stages are implemented below via the C API layer which
    // assembles modules. This core entry point validates the request shape.
    if (request.sources == nullptr && request.source_count > 0) {
        return Status::INVALID_ARGUMENT;
    }
    if (request.source_count < 0 || request.source_count > config_.limits.max_sources) {
        return Status::INVALID_ARGUMENT;
    }
    return Status::OK;
}

} // namespace yalla
