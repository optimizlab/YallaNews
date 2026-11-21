#ifndef YALLA_HTML_TEXT_EXTRACTOR_H
#define YALLA_HTML_TEXT_EXTRACTOR_H

#include <string>

namespace yalla {

// Lightweight HTML text extractor. Removes script/style/nav/footer and other
// obvious noise tags, decodes common HTML entities, and collapses whitespace.
// Intentionally not a full browser engine; the host supplies rendered text
// when JavaScript rendering is required.
class HtmlTextExtractor {
public:
    static std::string extract(const char* html);
    static std::string extract(const std::string& html);

private:
    static std::string decode_entities(const std::string& s);
    static bool is_noise_tag(const std::string& tag);
};

} // namespace yalla

#endif // YALLA_HTML_TEXT_EXTRACTOR_H
