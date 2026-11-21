#ifndef YALLA_TEXT_NORMALIZER_H
#define YALLA_TEXT_NORMALIZER_H

#include <string>

namespace yalla {

// Text normalization: whitespace, punctuation, and control-character cleanup.
// Arabic-specific normalization lives in the language layer so the original
// text is preserved separately.
class TextNormalizer {
public:
    static std::string normalize_whitespace(const std::string& text);
    static std::string strip_control_chars(const std::string& text);
};

} // namespace yalla

#endif // YALLA_TEXT_NORMALIZER_H
