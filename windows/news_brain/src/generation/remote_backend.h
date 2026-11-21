#ifndef YALLA_REMOTE_BACKEND_H
#define YALLA_REMOTE_BACKEND_H

#include "core/job_context.h"
#include "yalla_generation_backend.h"

#include <string>

namespace yalla {

// Optional adapter for a model hosted outside the device. The host controls
// networking, credentials and privacy. Only structured information is sent,
// never the complete original source unless explicitly authorized.
class RemoteGenerationBackend : public IGenerationBackend {
public:
    RemoteGenerationBackend(JobContext& job, std::string endpoint,
                            int32_t timeout_ms = 10000, size_t max_response_bytes = 65536);

    BackendCapabilities capabilities() const override;
    Status generate(const GenerationRequest& request, GenerationResult& result) override;

private:
    JobContext& job_;
    std::string endpoint_;
    int32_t timeout_ms_;
    size_t max_response_bytes_;
};

} // namespace yalla

#endif // YALLA_REMOTE_BACKEND_H
