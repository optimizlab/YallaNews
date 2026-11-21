#include "text_normalizer.h"

#include <cctype>

namespace yalla {

std::string TextNormalizer::normalize_whitespace(const std::string& text) {
    std::string out;
    out.reserve(text.size());
    bool prev_space = false;
    for (char c : text) {
        if (c == '\n') {
            out += '\n';
            prev_space = false;
        } else if (std::isspace((unsigned char)c)) {
            if (!prev_space) { out += ' '; prev_space = true; }
        } else {
            out += c;
            prev_space = false;
        }
    }
    return out;
}

std::string TextNormalizer::strip_control_chars(const std::string& text) {
    std::string out;
    out.reserve(text.size());
    for (char c : text) {
        unsigned char uc = (unsigned char)c;
        if (uc < 0x20 && c != '\n' && c != '\t') continue;
        if (uc == 0x7F) continue;
        out += c;
    }
    return out;
}

} // namespace yalla
