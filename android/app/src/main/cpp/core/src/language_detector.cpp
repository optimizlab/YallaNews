#include "yalla_core.h"
#include <string>
#include <vector>
#include <algorithm>
#include <cctype>
#include <unordered_map>
#include <array>

// Enhanced language detection with n-gram profiles
// Lightweight implementation suitable for mobile (no external model files)

struct YallaLanguageDetector {
    // Arabic Unicode ranges
    static constexpr uint32_t ARABIC_START = 0x0600;
    static constexpr uint32_t ARABIC_END = 0x06FF;
    static constexpr uint32_t ARABIC_EXT_START = 0x0750;
    static constexpr uint32_t ARABIC_EXT_END = 0x077F;
    static constexpr uint32_t ARABIC_PRES_START = 0x0FB50;
    static constexpr uint32_t ARABIC_PRES_END = 0x0FDFF;
    static constexpr uint32_t ARABIC_PRES2_START = 0x0FE70;
    static constexpr uint32_t ARABIC_PRES2_END = 0x0FEFF;

    // French-specific characters (with accents)
    static constexpr std::array<uint32_t, 16> FRENCH_CHARS = {
        0x00E0, 0x00E2, 0x00E4, 0x00E7, 0x00E8, 0x00E9, 0x00EA, 0x00EB, // àâäçèéêë
        0x00EE, 0x00EF, 0x00F4, 0x00F6, 0x00F9, 0x00FB, 0x00FC,          // îïôöùûü
        0x0153 // œ
    };

    // Common French trigrams for n-gram detection
    static constexpr std::array<const char*, 50> FRENCH_TRIGRAMS = {
        "ent", "que", "les", "ait", "ion", "tion", "ment", "eur", "ans", "des",
        "par", "con", "une", "pour", "dans", "sur", "est", "qui", "lui", "avec",
        "che", "res", "ait", "our", "eur", "ers", "ain", "air", "eau", "eux",
        "ois", "ait", "ion", "ien", "ien", "ier", "ell", "lle", "ssi", "tio",
        "nne", "tte", "rre", "ppe", "sse", "mme", "nne", "vou", "vou", "vou"
    };

    // Common English trigrams
    static constexpr std::array<const char*, 50> ENGLISH_TRIGRAMS = {
        "the", "and", "ing", "her", "hat", "his", "tha", "ere", "for", "ent",
        "ion", "tio", "ati", "ver", "all", "wit", "thi", "his", "oft", "ith",
        "oul", "out", "was", "you", "are", "not", "but", "his", "from", "they",
        "she", "will", "would", "there", "their", "what", "this", "that", "with",
        "have", "has", "had", "were", "been", "more", "some", "time", "very",
        "when", "come", "could", "than", "then", "now", "like", "just", "him"
    };

    bool is_arabic_char(uint32_t cp) const {
        return (cp >= ARABIC_START && cp <= ARABIC_END) ||
               (cp >= ARABIC_EXT_START && cp <= ARABIC_EXT_END) ||
               (cp >= ARABIC_PRES_START && cp <= ARABIC_PRES_END) ||
               (cp >= ARABIC_PRES2_START && cp <= ARABIC_PRES2_END);
    }

    bool is_latin_char(uint32_t cp) const {
        return (cp >= 0x0041 && cp <= 0x007A) || // Basic Latin
               (cp >= 0x00C0 && cp <= 0x00FF) || // Latin-1 Supplement
               (cp >= 0x0100 && cp <= 0x017F);   // Latin Extended-A
    }

    bool is_french_char(uint32_t cp) const {
        for (auto c : FRENCH_CHARS) if (cp == c) return true;
        return false;
    }

    // Extract trigrams from text (lowercase)
    std::vector<std::string> extract_trigrams(const std::string& text) const {
        std::vector<std::string> trigrams;
        std::string lower = text;
        std::transform(lower.begin(), lower.end(), lower.begin(),
            [](unsigned char c) { return std::tolower(c); });

        for (size_t i = 0; i + 2 < lower.size(); ++i) {
            char c1 = lower[i], c2 = lower[i+1], c3 = lower[i+2];
            if (std::isalpha(static_cast<unsigned char>(c1)) &&
                std::isalpha(static_cast<unsigned char>(c2)) &&
                std::isalpha(static_cast<unsigned char>(c3))) {
                trigrams.emplace_back(lower.substr(i, 3));
            }
        }
        return trigrams;
    }

    // Score text against trigram profile
    float score_trigrams(const std::vector<std::string>& trigrams,
                         const std::array<const char*, 50>& profile) const {
        if (trigrams.empty()) return 0.0f;

        std::unordered_map<std::string, int> freq;
        for (const auto& t : trigrams) freq[t]++;

        int matches = 0;
        for (const auto& p : profile) {
            auto it = freq.find(p);
            if (it != freq.end()) matches += it->second;
        }
        return static_cast<float>(matches) / trigrams.size();
    }
};

extern "C" {

YALLA_CORE_EXPORT YallaLanguageDetectorHandle yalla_language_detector_create() {
    return new YallaLanguageDetector();
}

YALLA_CORE_EXPORT void yalla_language_detector_destroy(YallaLanguageDetectorHandle handle) {
    if (handle) delete static_cast<YallaLanguageDetector*>(handle);
}

YALLA_CORE_EXPORT YallaLanguage yalla_language_detector_detect(YallaLanguageDetectorHandle handle,
    const char* text, float* confidence) {
    if (!handle || !text) {
        if (confidence) *confidence = 0.0f;
        return YALLA_LANG_UNKNOWN;
    }

    auto* detector = static_cast<YallaLanguageDetector*>(handle);
    std::string str(text);

    int arabic_count = 0;
    int latin_count = 0;
    int french_count = 0;
    int total_alpha = 0;

    // Count Unicode code points
    for (size_t i = 0; i < str.size(); ) {
        uint32_t cp = 0;
        unsigned char c = str[i];
        if (c < 0x80) {
            cp = c;
            i += 1;
        } else if ((c & 0xE0) == 0xC0) {
            cp = ((c & 0x1F) << 6) | (str[i+1] & 0x3F);
            i += 2;
        } else if ((c & 0xF0) == 0xE0) {
            cp = ((c & 0x0F) << 12) | ((str[i+1] & 0x3F) << 6) | (str[i+2] & 0x3F);
            i += 3;
        } else if ((c & 0xF8) == 0xF0) {
            cp = ((c & 0x07) << 18) | ((str[i+1] & 0x3F) << 12) | ((str[i+2] & 0x3F) << 6) | (str[i+3] & 0x3F);
            i += 4;
        } else {
            i += 1;
            continue;
        }

        if (std::isalpha(static_cast<unsigned char>(cp)) || cp > 0x7F) {
            total_alpha++;
            if (detector->is_arabic_char(cp)) arabic_count++;
            else if (detector->is_latin_char(cp)) {
                latin_count++;
                if (detector->is_french_char(cp)) french_count++;
            }
        }
    }

    if (total_alpha == 0) {
        if (confidence) *confidence = 0.0f;
        return YALLA_LANG_UNKNOWN;
    }

    float arabic_ratio = static_cast<float>(arabic_count) / total_alpha;
    float latin_ratio = static_cast<float>(latin_count) / total_alpha;
    float french_ratio = static_cast<float>(french_count) / total_alpha;

    // Strong Arabic signal
    if (arabic_ratio > 0.3f) {
        if (confidence) *confidence = arabic_ratio;
        return YALLA_LANG_ARABIC;
    }

    // N-gram based French vs English detection for Latin text
    if (latin_ratio > 0.5f) {
        auto trigrams = detector->extract_trigrams(str);
        float french_score = detector->score_trigrams(trigrams, YallaLanguageDetector::FRENCH_TRIGRAMS);
        float english_score = detector->score_trigrams(trigrams, YallaLanguageDetector::ENGLISH_TRIGRAMS);

        // Combine character-based and n-gram signals
        float combined_french = (french_ratio * 0.6f) + (french_score * 0.4f);
        float combined_english = ((latin_ratio - french_ratio) * 0.6f) + (english_score * 0.4f);

        if (combined_french > 0.05f && combined_french > combined_english * 1.2f) {
            if (confidence) *confidence = combined_french;
            return YALLA_LANG_FRENCH;
        }

        if (confidence) *confidence = latin_ratio;
        return YALLA_LANG_ENGLISH;
    }

    if (confidence) *confidence = 0.0f;
    return YALLA_LANG_UNKNOWN;
}

YALLA_CORE_EXPORT const char* yalla_language_detector_normalize(YallaLanguageDetectorHandle handle,
    YallaLanguage lang, const char* text) {
    if (!handle || !text) return strdup("");

    auto* detector = static_cast<YallaLanguageDetector*>(handle);
    std::string str(text);
    std::string result;

    switch (lang) {
        case YALLA_LANG_ARABIC: {
            // Arabic normalization: remove diacritics, normalize hamza, etc.
            for (size_t i = 0; i < str.size(); ) {
                uint32_t cp = 0;
                unsigned char c = str[i];
                if (c < 0x80) {
                    cp = c;
                    i += 1;
                } else if ((c & 0xE0) == 0xC0) {
                    cp = ((c & 0x1F) << 6) | (str[i+1] & 0x3F);
                    i += 2;
                } else if ((c & 0xF0) == 0xE0) {
                    cp = ((c & 0x0F) << 12) | ((str[i+1] & 0x3F) << 6) | (str[i+2] & 0x3F);
                    i += 3;
                } else if ((c & 0xF8) == 0xF0) {
                    cp = ((c & 0x07) << 18) | ((str[i+1] & 0x3F) << 12) | ((str[i+2] & 0x3F) << 6) | (str[i+3] & 0x3F);
                    i += 4;
                } else {
                    i += 1;
                    continue;
                }

                // Normalize Arabic characters
                switch (cp) {
                    case 0x0622: case 0x0623: case 0x0625: case 0x0671: // آ أ إ ا
                        cp = 0x0627; break; // ا
                    case 0x0649: // ى
                        cp = 0x064A; break; // ي
                    case 0x0640: // Tatweel
                        continue; // Remove
                    // Diacritics (harakat) - remove
                    case 0x064B: case 0x064C: case 0x064D: case 0x064E:
                    case 0x064F: case 0x0650: case 0x0651: case 0x0652:
                    case 0x0653: case 0x0654: case 0x0655: case 0x0670:
                        continue;
                    default:
                        break;
                }

                // Encode back to UTF-8
                if (cp < 0x80) result += static_cast<char>(cp);
                else if (cp < 0x800) {
                    result += static_cast<char>(0xC0 | (cp >> 6));
                    result += static_cast<char>(0x80 | (cp & 0x3F));
                } else if (cp < 0x10000) {
                    result += static_cast<char>(0xE0 | (cp >> 12));
                    result += static_cast<char>(0x80 | ((cp >> 6) & 0x3F));
                    result += static_cast<char>(0x80 | (cp & 0x3F));
                }
            }
            break;
        }
        case YALLA_LANG_FRENCH: {
            // French normalization: lowercase, preserve accents, remove extra spaces
            bool last_space = false;
            for (size_t i = 0; i < str.size(); ) {
                uint32_t cp = 0;
                unsigned char c = str[i];
                if (c < 0x80) {
                    cp = c;
                    i += 1;
                } else if ((c & 0xE0) == 0xC0) {
                    cp = ((c & 0x1F) << 6) | (str[i+1] & 0x3F);
                    i += 2;
                } else if ((c & 0xF0) == 0xE0) {
                    cp = ((c & 0x0F) << 12) | ((str[i+1] & 0x3F) << 6) | (str[i+2] & 0x3F);
                    i += 3;
                } else if ((c & 0xF8) == 0xF0) {
                    cp = ((c & 0x07) << 18) | ((str[i+1] & 0x3F) << 12) | ((str[i+2] & 0x3F) << 6) | (str[i+3] & 0x3F);
                    i += 4;
                } else {
                    i += 1;
                    continue;
                }

                // Lowercase but preserve French accents
                uint32_t lower = cp;
                if (cp >= 0x0041 && cp <= 0x005A) lower = cp + 0x20; // A-Z
                else if (cp >= 0x00C0 && cp <= 0x00D6) lower = cp + 0x20; // À-Ö
                else if (cp >= 0x00D8 && cp <= 0x00DE) lower = cp + 0x20; // Ø-Þ
                else if (cp >= 0x0100 && cp <= 0x012E && (cp % 2 == 0)) lower = cp + 1; // Latin Extended-A

                if (std::isspace(static_cast<int>(lower))) {
                    if (!last_space) {
                        result += ' ';
                        last_space = true;
                    }
                } else {
                    // Encode back to UTF-8
                    if (lower < 0x80) result += static_cast<char>(lower);
                    else if (lower < 0x800) {
                        result += static_cast<char>(0xC0 | (lower >> 6));
                        result += static_cast<char>(0x80 | (lower & 0x3F));
                    } else if (lower < 0x10000) {
                        result += static_cast<char>(0xE0 | (lower >> 12));
                        result += static_cast<char>(0x80 | ((lower >> 6) & 0x3F));
                        result += static_cast<char>(0x80 | (lower & 0x3F));
                    }
                    last_space = false;
                }
            }
            break;
        }
        case YALLA_LANG_ENGLISH: {
            // English normalization: lowercase, remove extra spaces
            bool last_space = false;
            for (char c : str) {
                char lower = std::tolower(static_cast<unsigned char>(c));
                if (std::isspace(static_cast<unsigned char>(lower))) {
                    if (!last_space) {
                        result += ' ';
                        last_space = true;
                    }
                } else {
                    result += lower;
                    last_space = false;
                }
            }
            break;
        }
        default:
            result = str;
            break;
    }

    return strdup(result.c_str());
}

} // extern "C"