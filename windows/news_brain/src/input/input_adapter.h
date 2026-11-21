#ifndef YALLA_INPUT_ADAPTER_H
#define YALLA_INPUT_ADAPTER_H

#include "core/job_context.h"
#include "yalla_errors.h"
#include "yalla_editorial.h"

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace yalla {

// A single normalized input source with both raw and normalized forms kept
// separate (raw_content is never overwritten by normalized_content).
struct NormalizedSource {
    std::string source_id;
    std::string raw_content;
    std::string normalized_content;
    std::string title;
    std::string url;
    std::string publisher;
    int64_t published_at = 0;
    std::string detected_language;
    std::vector<std::string> paragraphs;
};

// InputAdapter accepts content from different sources without requiring the
// host to provide perfectly cleaned text. It validates UTF-8, normalizes,
// decodes HTML entities, strips obvious markup noise, detects repeated blocks,
// segments paragraphs, and enforces input-size limits.
class InputAdapter {
public:
    explicit InputAdapter(JobContext& job);

    // Adapt a single source into a NormalizedSource. Returns Status::INPUT_TOO_LARGE
    // when content exceeds configured limits. Never overwrites raw_content.
    Status adapt(const char* text, const char* language, const char* title,
                 const char* source_url, const char* publisher, int64_t published_at,
                 NormalizedSource& out);

private:
    JobContext& job_;
};

} // namespace yalla

#endif // YALLA_INPUT_ADAPTER_H
