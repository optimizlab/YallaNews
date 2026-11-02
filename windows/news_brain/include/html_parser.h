#ifndef HTML_PARSER_H
#define HTML_PARSER_H

#include <string>
#include <vector>
#include <map>
#include <memory>

namespace newsbrain {

struct RawHtmlNode {
    int id = -1;
    int parentId = -1;
    std::string tag;
    std::string text;
    std::map<std::string, std::string> attributes;
    std::vector<int> childrenIds;

    std::string getAttribute(const std::string& name) const {
        auto it = attributes.find(name);
        return (it != attributes.end()) ? it->second : "";
    }

    bool hasAttribute(const std::string& name) const {
        return attributes.find(name) != attributes.end();
    }
};

class HtmlParser {
public:
    HtmlParser();
    ~HtmlParser();

    // Parses raw HTML string into a tree of RawHtmlNode
    std::vector<RawHtmlNode> parse(const std::string& html);

    // Entity decoder utility
    static std::string decodeEntities(const std::string& text);

    // Fast trim utility
    static std::string trim(const std::string& s);

    // To lowercase utility
    static std::string toLower(const std::string& s);
};

} // namespace newsbrain

#endif // HTML_PARSER_H
