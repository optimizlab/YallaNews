#include "local_backend.h"
#include "yalla_editorial.h"

namespace yalla {

LocalGenerationBackend::LocalGenerationBackend(JobContext& job, std::string model_path)
    : job_(job), model_path_(std::move(model_path)) {}

BackendCapabilities LocalGenerationBackend::capabilities() const {
    BackendCapabilities cap;
    cap.supports_arabic = true;
    cap.supports_french = true;
    cap.supports_english = true;
    cap.supports_streaming = false;
    cap.max_output_bytes = report_.max_output_length;
    cap.deterministic = false;
    return cap;
}

LocalGenerationBackend::CapabilityReport LocalGenerationBackend::declare_capabilities() const {
    return report_;
}

bool LocalGenerationBackend::fits_budget(size_t budget_bytes) const {
    size_t total = report_.model_file_size + report_.peak_resident_memory +
                   report_.context_memory + report_.inference_workspace;
    return total <= budget_bytes;
}

Status LocalGenerationBackend::generate(const GenerationRequest& request,
                                         GenerationResult& result) {
    // Model not loaded in the core; local generation is a host-side integration.
    result.status = Status::GENERATION_FAILED;
    result.error_message = "local model backend not loaded into core";
    return result.status;
}

} // namespace yalla
