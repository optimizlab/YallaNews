#include "html_text_extractor.h"

#include <algorithm>
#include <cctype>
#include <cstring>

namespace yalla {

static bool is_space(char c) { return c == ' ' || c == '\t' || c == '\n' || c == '\r'; }

bool HtmlTextExtractor::is_noise_tag(const std::string& tag) {
    static const char* noise[] = {"script", "style", "nav", "footer", "header",
                                  "aside", "iframe", "noscript", "form", "button"};
    for (const char* n : noise) {
        if (tag.size() == std::strlen(n) &&
            std::equal(tag.begin(), tag.end(), n,
                       [](char a, char b) { return std::tolower((unsigned char)a) == std::tolower((unsigned char)b); })) {
            return true;
        }
    }
    return false;
}

std::string HtmlTextExtractor::decode_entities(const std::string& s) {
    std::string out;
    out.reserve(s.size());
    for (size_t i = 0; i < s.size(); ++i) {
        if (s[i] == '&') {
            size_t end = s.find(';', i + 1);
            if (end != std::string::npos && end - i <= 8) {
                std::string ent = s.substr(i + 1, end - i - 1);
                if (ent == "amp") { out += '&'; }
                else if (ent == "lt") { out += '<'; }
                else if (ent == "gt") { out += '>'; }
                else if (ent == "quot") { out += '"'; }
                else if (ent == "apos") { out += '\''; }
                else if (ent == "nbsp") { out += ' '; }
                else if (ent == "iquest") { out += char(0xC2); out += char(0xBF); } // ¡
                else if (ent == "iexcl") { out += char(0xC2); out += char(0xA1); }   // ¡
                else { out.append(s, i, end - i + 1); }
                i = end;
                continue;
            }
        }
        out += s[i];
    }
    return out;
}

std::string HtmlTextExtractor::extract(const char* html) {
    return extract(html ? std::string(html) : std::string());
}

std::string HtmlTextExtractor::extract(const std::string& html) {
    std::string out;
    out.reserve(html.size());
    size_t i = 0;
    bool in_tag = false;
    std::string tag_name;
    while (i < html.size()) {
        char c = html[i];
        if (!in_tag && c == '<') {
            in_tag = true;
            tag_name.clear();
            ++i;
            continue;
        }
        if (in_tag) {
            if (c == '>' || is_space(c) || c == '/') {
                if (c == '>') {
                    bool closing = !tag_name.empty() && tag_name[0] == '/';
                    std::string name = tag_name;
                    if (!name.empty() && name[0] == '/') name.erase(0, 1);
                    if (!closing && is_noise_tag(name)) {
                        // skip until closing tag of this noise element
                        std::string close = "</" + name + ">";
                        size_t endpos = html.find(close, i + 1);
                        if (endpos != std::string::npos) {
                            i = endpos + close.size();
                        } else {
                            i = html.size();
                        }
                        in_tag = false;
                        continue;
                    }
                    in_tag = false;
                    out += ' ';
                    ++i;
                    continue;
                }
                if (std::isalpha((unsigned char)c)) tag_name += c;
                ++i;
                continue;
            }
            tag_name += c;
            ++i;
            continue;
        }
        out += c;
        ++i;
    }

    std::string decoded = decode_entities(out);

    // Collapse whitespace but preserve paragraph breaks (newlines).
    std::string result;
    result.reserve(decoded.size());
    bool prev_space = false;
    for (char c : decoded) {
        if (is_space(c)) {
            if (c == '\n') {
                result += '\n';
                prev_space = false;
            } else if (!prev_space) {
                result += ' ';
                prev_space = true;
            }
        } else {
            result += c;
            prev_space = false;
        }
    }
    return result;
}

} // namespace yalla
