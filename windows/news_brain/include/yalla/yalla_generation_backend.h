#ifndef YALLA_GENERATION_BACKEND_H
#define YALLA_GENERATION_BACKEND_H

#include "yalla_types.h"
#include "yalla_errors.h"

#include <cstddef>
#include <cstdint>
#include <memory>
#include <string>
#include <vector>

namespace yalla {

// Forward declarations of editorial value types defined in yalla_editorial.h.
struct Fact;
struct Entity;
struct Evidence;
struct EventRepresentation;
struct EditorialPlan;
struct GenerationOptions;
struct GenerationResult;
struct CancellationToken;

// Capabilities reported by a generation backend.
struct BackendCapabilities {
    bool supports_arabic = false;
    bool supports_french = false;
    bool supports_english = false;
    bool supports_streaming = false;
    size_t max_output_bytes = 0;
    bool deterministic = true;
};

// Generation request payload.
struct GenerationRequest {
    const EditorialPlan* plan = nullptr;
    const std::vector<Fact>* facts = nullptr;
    const std::vector<Evidence>* evidence = nullptr;
    const GenerationOptions* options = nullptr;
    CancellationToken* cancellation = nullptr;
};

// Abstract generation backend interface. The core never depends on a
// specific backend; backends are pluggable and optional.
class IGenerationBackend {
public:
    virtual ~IGenerationBackend() = default;

    virtual BackendCapabilities capabilities() const = 0;

    // Generate article text. Returns Status::OK on success.
    // Must respect cancellation and never block indefinitely.
    virtual Status generate(const GenerationRequest& request,
                            GenerationResult& result) = 0;
};

} // namespace yalla

#endif // YALLA_GENERATION_BACKEND_H
