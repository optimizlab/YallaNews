#include "language_detector.h"

#include <algorithm>
#include <cctype>
#include <unordered_set>

namespace yalla {

namespace {
bool is_arabic_char(unsigned char c) {
    // UTF-8 Arabic block lead bytes: 0xD8 (U+0600-06FF) and 0xD9 (U+0750-077F)
    return c == 0xD8 || c == 0xD9;
}

const std::unordered_set<std::string>& french_stopwords() {
    static const std::unordered_set<std::string> s = {
        "le","la","les","un","une","des","et","ou","de","du","au","aux","en","que","qui","est","pas",
        "pour","sur","avec","sans","dans","par","ce","cet","cette","ces","mon","ma","mes","son","sa",
        "ses","etre","avoir","faire","dire","il","elle","nous","vous","ils","elles","a","et","y","l"
    };
    return s;
}
const std::unordered_set<std::string>& english_stopwords() {
    static const std::unordered_set<std::string> s = {
        "the","a","an","and","or","of","to","in","is","it","that","for","on","with","as","was","are",
        "be","been","this","that","these","those","not","at","by","from","you","we","they","he","she",
        "his","her","their","our","your","my","i","me","him","them","us"
    };
    return s;
}
} // namespace

int LanguageDetector::score_arabic(const std::string& text) {
    int count = 0;
    for (size_t i = 0; i + 1 < text.size(); ++i) {
        if (is_arabic_char((unsigned char)text[i])) { ++count; ++i; }
    }
    return count;
}

int LanguageDetector::score_french(const std::string& text) {
    std::string lower = text;
    std::transform(lower.begin(), lower.end(), lower.begin(),
                   [](unsigned char c){ return std::tolower(c); });
    int score = 0;
    size_t pos = 0;
    while ((pos = lower.find(' ', pos)) != std::string::npos) {
        size_t start = pos;
        size_t end = lower.find(' ', start + 1);
        std::string word = (end == std::string::npos) ? lower.substr(start + 1)
                                                       : lower.substr(start + 1, end - start - 1);
        if (french_stopwords().count(word)) ++score;
        pos = end;
    }
    return score;
}

int LanguageDetector::score_english(const std::string& text) {
    std::string lower = text;
    std::transform(lower.begin(), lower.end(), lower.begin(),
                   [](unsigned char c){ return std::tolower(c); });
    int score = 0;
    size_t pos = 0;
    while ((pos = lower.find(' ', pos)) != std::string::npos) {
        size_t start = pos;
        size_t end = lower.find(' ', start + 1);
        std::string word = (end == std::string::npos) ? lower.substr(start + 1)
                                                       : lower.substr(start + 1, end - start - 1);
        if (english_stopwords().count(word)) ++score;
        pos = end;
    }
    return score;
}

Language LanguageDetector::detect(const std::string& text) const {
    int ar = score_arabic(text);
    int fr = score_french(text);
    int en = score_english(text);
    int best = std::max({ar, fr, en});
    if (best <= 0) return Language::Unknown;
    if (ar == best) return Language::Arabic;
    if (fr == best) return Language::French;
    return Language::English;
}

Language LanguageDetector::detect_paragraph(const std::string& paragraph) const {
    return detect(paragraph);
}

std::string LanguageDetector::language_code(Language lang) const {
    switch (lang) {
        case Language::Arabic: return "ar";
        case Language::French: return "fr";
        case Language::English: return "en";
        default: return "und";
    }
}

Language LanguageDetector::language_from_code(const std::string& code) const {
    if (code == "ar") return Language::Arabic;
    if (code == "fr") return Language::French;
    if (code == "en") return Language::English;
    return Language::Unknown;
}

bool LanguageDetector::is_mixed(const std::string& text) const {
    int ar = score_arabic(text);
    int fr = score_french(text);
    int en = score_english(text);
    int present = (ar > 0 ? 1 : 0) + (fr > 0 ? 1 : 0) + (en > 0 ? 1 : 0);
    return present >= 2;
}

} // namespace yalla
