#include "../include/html_parser.h"
#include <sstream>
#include <algorithm>
#include <cctype>
#include <unordered_set>

namespace newsbrain {

static const std::unordered_set<std::string> kVoidTags = {
    "area", "base", "br", "col", "embed", "hr", "img", "input",
    "link", "meta", "param", "source", "track", "wbr"
};

static const std::unordered_set<std::string> kIgnoredContentTags = {
    "script", "style", "svg", "noscript", "canvas", "template"
};

HtmlParser::HtmlParser() = default;
HtmlParser::~HtmlParser() = default;

std::string HtmlParser::toLower(const std::string& s) {
    std::string res = s;
    std::transform(res.begin(), res.end(), res.begin(), [](unsigned char c) {
        return std::tolower(c);
    });
    return res;
}

std::string HtmlParser::trim(const std::string& s) {
    // Never decrement end() for an empty/all-whitespace string. MSVC's debug
    // iterator checks correctly abort on that operation.
    const auto first = s.find_first_not_of(" \t\r\n\f\v");
    if (first == std::string::npos) return {};
    const auto last = s.find_last_not_of(" \t\r\n\f\v");
    return s.substr(first, last - first + 1);
}

std::string HtmlParser::decodeEntities(const std::string& text) {
    std::string result;
    result.reserve(text.size());

    size_t i = 0;
    while (i < text.size()) {
        if (text[i] == '&') {
            size_t semi = text.find(';', i);
            if (semi != std::string::npos && semi - i <= 10) {
                std::string entity = text.substr(i + 1, semi - i - 1);
                if (entity == "nbsp") {
                    result += ' ';
                    i = semi + 1;
                    continue;
                } else if (entity == "amp") {
                    result += '&';
                    i = semi + 1;
                    continue;
                } else if (entity == "lt") {
                    result += '<';
                    i = semi + 1;
                    continue;
                } else if (entity == "gt") {
                    result += '>';
                    i = semi + 1;
                    continue;
                } else if (entity == "quot") {
                    result += '"';
                    i = semi + 1;
                    continue;
                } else if (entity == "apos" || entity == "#39" || entity == "#039") {
                    result += '\'';
                    i = semi + 1;
                    continue;
                } else if (entity.size() > 1 && entity[0] == '#') {
                    // Numeric entity
                    try {
                        int code = 0;
                        if (entity[1] == 'x' || entity[1] == 'X') {
                            code = std::stoi(entity.substr(2), nullptr, 16);
                        } else {
                            code = std::stoi(entity.substr(1));
                        }
                        if (code > 0 && code < 128) {
                            result += static_cast<char>(code);
                            i = semi + 1;
                            continue;
                        }
                    } catch (...) {}
                }
            }
        }
        result += text[i];
        i++;
    }
    return result;
}

static void parseAttributes(const std::string& attrStr, std::map<std::string, std::string>& attrs) {
    size_t i = 0;
    size_t n = attrStr.size();

    while (i < n) {
        // Skip whitespace
        while (i < n && std::isspace(static_cast<unsigned char>(attrStr[i]))) i++;
        if (i >= n) break;

        // Attribute name
        size_t nameStart = i;
        while (i < n && !std::isspace(static_cast<unsigned char>(attrStr[i])) &&
               attrStr[i] != '=' && attrStr[i] != '/' && attrStr[i] != '>') {
            i++;
        }
        std::string name = HtmlParser::toLower(attrStr.substr(nameStart, i - nameStart));
        if (name.empty()) {
            i++;
            continue;
        }

        // Skip whitespace before '='
        while (i < n && std::isspace(static_cast<unsigned char>(attrStr[i]))) i++;

        std::string value;
        if (i < n && attrStr[i] == '=') {
            i++; // skip '='
            while (i < n && std::isspace(static_cast<unsigned char>(attrStr[i]))) i++;

            if (i < n && (attrStr[i] == '"' || attrStr[i] == '\'')) {
                char quote = attrStr[i];
                i++; // skip quote
                size_t valStart = i;
                while (i < n && attrStr[i] != quote) {
                    i++;
                }
                value = attrStr.substr(valStart, i - valStart);
                if (i < n && attrStr[i] == quote) i++; // skip closing quote
            } else {
                size_t valStart = i;
                while (i < n && !std::isspace(static_cast<unsigned char>(attrStr[i])) &&
                       attrStr[i] != '>') {
                    i++;
                }
                value = attrStr.substr(valStart, i - valStart);
            }
        }

        attrs[name] = HtmlParser::decodeEntities(value);
    }
}

std::vector<RawHtmlNode> HtmlParser::parse(const std::string& html) {
    std::vector<RawHtmlNode> nodes;
    nodes.reserve(1024);

    // Root document node
    RawHtmlNode root;
    root.id = 0;
    root.parentId = -1;
    root.tag = "document";
    nodes.push_back(root);

    std::vector<int> nodeStack;
    nodeStack.push_back(0);

    size_t i = 0;
    size_t n = html.size();
    std::string textBuffer;

    auto flushText = [&]() {
        std::string cleaned = trim(decodeEntities(textBuffer));
        textBuffer.clear();
        if (!cleaned.empty() && !nodeStack.empty()) {
            int currentId = nodeStack.back();
            if (!nodes[currentId].text.empty()) {
                nodes[currentId].text += " ";
            }
            nodes[currentId].text += cleaned;
        }
    };

    while (i < n) {
        if (html[i] == '<') {
            // Check for HTML comment <!-- ... -->
            if (i + 3 < n && html.substr(i, 4) == "<!--") {
                size_t endComment = html.find("-->", i + 4);
                if (endComment != std::string::npos) {
                    i = endComment + 3;
                } else {
                    i = n;
                }
                continue;
            }

            // Check for CDATA <![CDATA[ ... ]]>
            if (i + 8 < n && html.substr(i, 9) == "<![CDATA[") {
                size_t endCdata = html.find("]]>", i + 9);
                if (endCdata != std::string::npos) {
                    textBuffer += html.substr(i + 9, endCdata - (i + 9));
                    i = endCdata + 3;
                } else {
                    i = n;
                }
                continue;
            }

            // Check for DOCTYPE <!DOCTYPE ... >
            if (i + 8 < n && toLower(html.substr(i, 9)) == "<!doctype") {
                size_t endDoc = html.find('>', i);
                i = (endDoc != std::string::npos) ? endDoc + 1 : n;
                continue;
            }

            // Closing tag </tag>
            if (i + 1 < n && html[i + 1] == '/') {
                flushText();
                size_t tagEnd = html.find('>', i + 2);
                if (tagEnd == std::string::npos) break;

                std::string closingTag = toLower(trim(html.substr(i + 2, tagEnd - (i + 2))));
                i = tagEnd + 1;

                // Pop stack until matching tag found or root reached
                while (nodeStack.size() > 1) {
                    int topId = nodeStack.back();
                    nodeStack.pop_back();
                    if (nodes[topId].tag == closingTag) {
                        break;
                    }
                }
                continue;
            }

            // Opening or self-closing tag <tag ... >
            size_t tagEnd = html.find('>', i + 1);
            if (tagEnd == std::string::npos) break;

            flushText();

            std::string tagContent = html.substr(i + 1, tagEnd - (i + 1));
            bool isSelfClosing = false;
            if (!tagContent.empty() && tagContent.back() == '/') {
                isSelfClosing = true;
                tagContent.pop_back();
            }

            // Extract tag name and attribute string
            size_t spacePos = tagContent.find_first_of(" \t\r\n");
            std::string tagName;
            std::string attrStr;

            if (spacePos != std::string::npos) {
                tagName = toLower(trim(tagContent.substr(0, spacePos)));
                attrStr = tagContent.substr(spacePos + 1);
            } else {
                tagName = toLower(trim(tagContent));
            }

            if (tagName.empty()) {
                i = tagEnd + 1;
                continue;
            }

            // Check if this tag has content we want to skip or treat specially
            if (kIgnoredContentTags.find(tagName) != kIgnoredContentTags.end()) {
                // If it's <script type="application/ld+json">, we want the JSON-LD content!
                std::map<std::string, std::string> tempAttrs;
                parseAttributes(attrStr, tempAttrs);
                auto typeIt = tempAttrs.find("type");
                bool isJsonLd = (typeIt != tempAttrs.end() && 
                                 typeIt->second.find("ld+json") != std::string::npos);

                std::string closePattern = "</" + tagName + ">";
                std::string lowerHtml = toLower(html);
                size_t endPos = lowerHtml.find(closePattern, tagEnd + 1);

                if (isJsonLd && endPos != std::string::npos) {
                    std::string ldContent = html.substr(tagEnd + 1, endPos - (tagEnd + 1));
                    RawHtmlNode ldNode;
                    ldNode.id = static_cast<int>(nodes.size());
                    ldNode.parentId = nodeStack.back();
                    ldNode.tag = "script";
                    ldNode.attributes = tempAttrs;
                    ldNode.text = trim(ldContent);
                    nodes.push_back(ldNode);
                    nodes[nodeStack.back()].childrenIds.push_back(ldNode.id);
                }

                if (endPos != std::string::npos) {
                    i = endPos + closePattern.size();
                } else {
                    i = n;
                }
                continue;
            }

            // Normal node
            RawHtmlNode newNode;
            newNode.id = static_cast<int>(nodes.size());
            newNode.parentId = nodeStack.empty() ? 0 : nodeStack.back();
            newNode.tag = tagName;
            parseAttributes(attrStr, newNode.attributes);

            int newId = newNode.id;
            nodes.push_back(newNode);
            nodes[newNode.parentId].childrenIds.push_back(newId);

            i = tagEnd + 1;

            bool isVoid = (kVoidTags.find(tagName) != kVoidTags.end());
            if (!isVoid && !isSelfClosing) {
                nodeStack.push_back(newId);
            }
        } else {
            textBuffer += html[i];
            i++;
        }
    }

    flushText();
    return nodes;
}

} // namespace newsbrain
