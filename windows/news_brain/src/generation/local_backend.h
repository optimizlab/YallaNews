#ifndef YALLA_LOCAL_BACKEND_H
#define YALLA_LOCAL_BACKEND_H

#include "core/job_context.h"
#include "yalla_generation_backend.h"

#include <string>

namespace yalla {

// Optional separately-budgeted model integration (e.g. llama.cpp through this
// backend only). Never linked as a mandatory dependency of the core.
class LocalGenerationBackend : public IGenerationBackend {
public:
    struct CapabilityReport {
        size_t model_file_size = 0;
        size_t peak_resident_memory = 0;
        size_t context_memory = 0;
        size_t inference_workspace = 0;
        std::vector<std::string> supported_languages;
        size_t max_output_length = 0;
        std::string hardware_requirements;
    };

    LocalGenerationBackend(JobContext& job, std::string model_path);

    BackendCapabilities capabilities() const override;
    Status generate(const GenerationRequest& request, GenerationResult& result) override;

    // Declares model resource requirements; core rejects models exceeding budget.
    CapabilityReport declare_capabilities() const;
    bool fits_budget(size_t budget_bytes) const;

private:
    JobContext& job_;
    std::string model_path_;
    CapabilityReport report_;
};

} // namespace yalla

#endif // YALLA_LOCAL_BACKEND_H
