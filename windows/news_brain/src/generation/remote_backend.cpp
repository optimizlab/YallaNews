#include "remote_backend.h"
#include "yalla_editorial.h"

namespace yalla {

RemoteGenerationBackend::RemoteGenerationBackend(JobContext& job, std::string endpoint,
                                                  int32_t timeout_ms, size_t max_response_bytes)
    : job_(job), endpoint_(std::move(endpoint)), timeout_ms_(timeout_ms),
      max_response_bytes_(max_response_bytes) {}

BackendCapabilities RemoteGenerationBackend::capabilities() const {
    BackendCapabilities cap;
    cap.supports_arabic = true;
    cap.supports_french = true;
    cap.supports_english = true;
    cap.supports_streaming = false;
    cap.max_output_bytes = max_response_bytes_;
    cap.deterministic = false;
    return cap;
}

Status RemoteGenerationBackend::generate(const GenerationRequest& request,
                                          GenerationResult& result) {
    // No HTTP client dependency in the core: the host must inject a transport.
    // This backend reports unsupported until the host wires a fetcher.
    result.status = Status::GENERATION_FAILED;
    result.error_message = "remote backend requires host-supplied HTTP transport";
    return result.status;
}

} // namespace yalla
