#include "arabic_normalizer.h"

namespace yalla {

namespace {
// Returns true when the byte at i begins a two-byte UTF-8 sequence in the
// Arabic block (lead byte 0xD8 or 0xD9).
bool is_arabic_lead(const std::string& s, size_t i) {
    if (i + 1 >= s.size()) return false;
    unsigned char lead = (unsigned char)s[i];
    return lead == 0xD8 || lead == 0xD9;
}
} // namespace

std::string ArabicNormalizer::normalize(const std::string& arabic_text) {
    // Lightweight normalization: strip diacritics (tashkeel) in the Arabic block
    // (U+064B-U+065F -> bytes 0xD8 0x8B..0x9F and 0xD9 0x80..0x9F).
    std::string out;
    out.reserve(arabic_text.size());
    for (size_t i = 0; i < arabic_text.size(); ++i) {
        if (is_arabic_lead(arabic_text, i)) {
            unsigned char trail = (unsigned char)arabic_text[i + 1];
            bool is_tashkeel = (arabic_text[i] == char(0xD8) && trail >= 0x8B && trail <= 0x9F);
            if (!is_tashkeel) {
                out += arabic_text[i];
                out += arabic_text[i + 1];
            }
            i += 1;
        } else {
            out += arabic_text[i];
        }
    }
    return out;
}

std::string ArabicNormalizer::normalize_for_matching(const std::string& arabic_text) {
    std::string n = normalize(arabic_text);
    // Map Alef variants (U+0622, U+0623, U+0625, U+0627) to plain Alef (U+0627)
    // and Alef Maksura (U+0649) to Ya (U+064A), Teh Marbuta (U+0629) to Heh (U+0647)
    // for matching only. Multi-byte UTF-8 handling below.
    std::string out;
    out.reserve(n.size());
    for (size_t i = 0; i < n.size(); ++i) {
        if (is_arabic_lead(n, i)) {
            unsigned char lead = (unsigned char)n[i];
            unsigned char trail = (unsigned char)n[i + 1];
            // U+0622 = D8 A2, U+0623 = D8 A3, U+0625 = D8 A5 -> map to D8 A7
            // U+0627 = D8 A7 already plain alef.
            // U+0649 = D9 A9 (alef maksura) -> D9 8A (ya)
            // U+0629 = D9 89 (teh marbuta) -> D9 47 (heh)
            bool mapped = false;
            if (lead == 0xD8 && (trail == 0xA2 || trail == 0xA3 || trail == 0xA5)) {
                out += char(0xD8); out += char(0xA7); mapped = true;
            } else if (lead == 0xD9 && trail == 0xA9) {
                out += char(0xD9); out += char(0x8A); mapped = true;
            } else if (lead == 0xD9 && trail == 0x89) {
                out += char(0xD9); out += char(0x47); mapped = true;
            }
            if (mapped) { i += 1; continue; }
            out += n[i];
            out += n[i + 1];
            i += 1;
        } else {
            out += n[i];
        }
    }
    return out;
}

} // namespace yalla
