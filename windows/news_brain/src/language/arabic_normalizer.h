#ifndef YALLA_ARABIC_NORMALIZER_H
#define YALLA_ARABIC_NORMALIZER_H

#include <string>

namespace yalla {

// Arabic normalization as an optional matching aid. Original text is always
// preserved separately; normalization must not destroy meaningful distinctions.
// Arabic, French and English names are never merged merely because spellings
// look similar.
class ArabicNormalizer {
public:
    // Returns a normalized form suitable for matching, leaving the original
    // string untouched.
    static std::string normalize(const std::string& arabic_text);

    // Maps common Arabic character variants (Alef variants, Ya, Teh Marbuta)
    // to a canonical representative for comparison only.
    static std::string normalize_for_matching(const std::string& arabic_text);
};

} // namespace yalla

#endif // YALLA_ARABIC_NORMALIZER_H
