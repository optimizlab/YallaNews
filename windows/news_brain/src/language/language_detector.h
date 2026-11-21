#ifndef YALLA_LANGUAGE_DETECTOR_H
#define YALLA_LANGUAGE_DETECTOR_H

#include <string>
#include <vector>

namespace yalla {

enum class Language { Unknown, Arabic, French, English };

// Detects Arabic, French and English. Identifies the dominant language and can
// tag the language of individual paragraphs. Heuristic, dictionary-free,
// suitable for the 16 MiB core. Translation is never performed automatically.
class LanguageDetector {
public:
    Language detect(const std::string& text) const;
    Language detect_paragraph(const std::string& paragraph) const;
    std::string language_code(Language lang) const;
    Language language_from_code(const std::string& code) const;

    // Returns true when more than one supported language has significant presence.
    bool is_mixed(const std::string& text) const;

private:
    static int score_arabic(const std::string& text);
    static int score_french(const std::string& text);
    static int score_english(const std::string& text);
};

} // namespace yalla

#endif // YALLA_LANGUAGE_DETECTOR_H
