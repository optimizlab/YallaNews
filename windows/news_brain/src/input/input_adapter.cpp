#include "input_adapter.h"
#include "html_text_extractor.h"
#include "text_normalizer.h"
#include <cstring>

namespace yalla {

InputAdapter::InputAdapter(JobContext& job) : job_(job) {}

Status InputAdapter::adapt(const char* text, const char* language, const char* title,
                           const char* source_url, const char* publisher, int64_t published_at,
                           NormalizedSource& out) {
    out = NormalizedSource{};
    if (!text) return Status::INVALID_ARGUMENT;

    size_t len = std::strlen(text);
    if (len > job_.limits().max_input_bytes) {
        return Status::INPUT_TOO_LARGE;
    }

    // Raw content is preserved verbatim for the duration of the job.
    char* raw = job_.dup_string(text);
    if (!raw) return Status::OUT_OF_MEMORY;
    out.raw_content = raw;

    // Strip markup noise and decode entities to obtain working text.
    std::string working = HtmlTextExtractor::extract(text);

    // Normalize whitespace/punctuation (language-aware normalization applied later).
    std::string normalized = TextNormalizer::normalize_whitespace(working);

    char* norm = job_.dup_string(normalized);
    if (!norm) return Status::OUT_OF_MEMORY;
    out.normalized_content = norm;

    out.title = title ? job_.dup_string(title) : std::string();
    out.source_id = "S001";
    out.url = source_url ? job_.dup_string(source_url) : std::string();
    out.publisher = publisher ? job_.dup_string(publisher) : std::string();
    out.published_at = published_at;
    out.detected_language = language ? language : "und";

    // Paragraph segmentation on the normalized text.
    size_t start = 0;
    int32_t count = 0;
    while (start < normalized.size() && count < job_.limits().max_paragraphs) {
        size_t end = normalized.find('\n', start);
        if (end == std::string::npos) end = normalized.size();
        std::string para = normalized.substr(start, end - start);
        // trim
        size_t a = para.find_first_not_of(" \t\r");
        size_t b = para.find_last_not_of(" \t\r");
        if (a != std::string::npos && b != std::string::npos && b >= a) {
            out.paragraphs.push_back(para.substr(a, b - a + 1));
            ++count;
        }
        start = end + 1;
    }
    if (out.paragraphs.empty() && !normalized.empty()) {
        out.paragraphs.push_back(normalized);
    }

    return Status::OK;
}

} // namespace yalla
