#include "yalla_core.h"
#include <string>
#include <vector>
#include <regex>
#include <algorithm>
#include <mutex>
#include <thread>
#include <chrono>
#include <sstream>
#include <map>
#include <set>
#include <unordered_map>
#include <cctype>
#include <nlohmann/json.hpp>

// Simple HTTP fetch using platform-specific code
#if defined(_WIN32)
#include <windows.h>
#include <winhttp.h>
#pragma comment(lib, "winhttp.lib")
#elif defined(__ANDROID__) || defined(__linux__)
#include <curl/curl.h>
#endif

using json = nlohmann::json;

// ============================================================================
// HTML Parser (adapted from news_brain)
// ============================================================================

struct RawHtmlNode {
    int id = -1;
    int parentId = -1;
    std::string tag;
    std::map<std::string, std::string> attributes;
    std::string text;
    std::vector<int> childrenIds;

    std::string getAttribute(const std::string& key) const {
        auto it = attributes.find(key);
        return it != attributes.end() ? it->second : "";
    }
    bool hasAttribute(const std::string& key) const {
        return attributes.find(key) != attributes.end();
    }
};

class HtmlParser {
public:
    std::vector<RawHtmlNode> parse(const std::string& html) {
        std::vector<RawHtmlNode> nodes;
        nodes.reserve(1024);

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
                // Comment
                if (i + 3 < n && html.substr(i, 4) == "<!--") {
                    size_t endComment = html.find("-->", i + 4);
                    if (endComment != std::string::npos) {
                        i = endComment + 3;
                    } else {
                        i = n;
                    }
                    continue;
                }
                // CDATA
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
                // DOCTYPE
                if (i + 8 < n && toLower(html.substr(i, 9)) == "<!doctype") {
                    size_t endDoc = html.find('>', i);
                    i = (endDoc != std::string::npos) ? endDoc + 1 : n;
                    continue;
                }
                // Closing tag
                if (i + 1 < n && html[i + 1] == '/') {
                    flushText();
                    size_t tagEnd = html.find('>', i + 2);
                    if (tagEnd == std::string::npos) break;
                    std::string closingTag = toLower(trim(html.substr(i + 2, tagEnd - (i + 2))));
                    i = tagEnd + 1;
                    while (nodeStack.size() > 1) {
                        int topId = nodeStack.back();
                        nodeStack.pop_back();
                        if (nodes[topId].tag == closingTag) break;
                    }
                    continue;
                }
                // Opening or self-closing tag
                size_t tagEnd = html.find('>', i + 1);
                if (tagEnd == std::string::npos) break;

                flushText();

                std::string tagContent = html.substr(i + 1, tagEnd - (i + 1));
                bool isSelfClosing = false;
                if (!tagContent.empty() && tagContent.back() == '/') {
                    isSelfClosing = true;
                    tagContent.pop_back();
                }

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

                // Special handling for script/style (ignore content except JSON-LD)
                static const std::unordered_set<std::string> kIgnoredContentTags = {
                    "script", "style", "svg", "noscript", "canvas", "template"
                };
                if (kIgnoredContentTags.find(tagName) != kIgnoredContentTags.end()) {
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

                static const std::unordered_set<std::string> kVoidTags = {
                    "area", "base", "br", "col", "embed", "hr", "img", "input",
                    "link", "meta", "param", "source", "track", "wbr"
                };
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

private:
    static std::string toLower(const std::string& s) {
        std::string res = s;
        std::transform(res.begin(), res.end(), res.begin(),
            [](unsigned char c) { return std::tolower(c); });
        return res;
    }

    static std::string trim(const std::string& s) {
        const auto first = s.find_first_not_of(" \t\r\n\f\v");
        if (first == std::string::npos) return {};
        const auto last = s.find_last_not_of(" \t\r\n\f\v");
        return s.substr(first, last - first + 1);
    }

    static std::string decodeEntities(const std::string& text) {
        std::string result;
        result.reserve(text.size());

        size_t i = 0;
        while (i < text.size()) {
            if (text[i] == '&') {
                size_t semi = text.find(';', i);
                if (semi != std::string::npos && semi - i <= 10) {
                    std::string entity = text.substr(i + 1, semi - i - 1);
                    if (entity == "nbsp") { result += ' '; i = semi + 1; continue; }
                    else if (entity == "amp") { result += '&'; i = semi + 1; continue; }
                    else if (entity == "lt") { result += '<'; i = semi + 1; continue; }
                    else if (entity == "gt") { result += '>'; i = semi + 1; continue; }
                    else if (entity == "quot") { result += '"'; i = semi + 1; continue; }
                    else if (entity == "apos" || entity == "#39" || entity == "#039") { result += '\''; i = semi + 1; continue; }
                    else if (entity.size() > 1 && entity[0] == '#') {
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
            while (i < n && std::isspace(static_cast<unsigned char>(attrStr[i]))) i++;
            if (i >= n) break;

            size_t nameStart = i;
            while (i < n && !std::isspace(static_cast<unsigned char>(attrStr[i])) &&
                   attrStr[i] != '=' && attrStr[i] != '/' && attrStr[i] != '>') {
                i++;
            }
            std::string name = toLower(attrStr.substr(nameStart, i - nameStart));
            if (name.empty()) { i++; continue; }

            while (i < n && std::isspace(static_cast<unsigned char>(attrStr[i]))) i++;

            std::string value;
            if (i < n && attrStr[i] == '=') {
                i++;
                while (i < n && std::isspace(static_cast<unsigned char>(attrStr[i]))) i++;

                if (i < n && (attrStr[i] == '"' || attrStr[i] == '\'')) {
                    char quote = attrStr[i];
                    i++;
                    size_t valStart = i;
                    while (i < n && attrStr[i] != quote) i++;
                    value = attrStr.substr(valStart, i - valStart);
                    if (i < n && attrStr[i] == quote) i++;
                } else {
                    size_t valStart = i;
                    while (i < n && !std::isspace(static_cast<unsigned char>(attrStr[i])) &&
                           attrStr[i] != '>') {
                        i++;
                    }
                    value = attrStr.substr(valStart, i - valStart);
                }
            }

            attrs[name] = decodeEntities(value);
        }
    }
};

// ============================================================================
// Page Scanner (adapted from news_brain)
// ============================================================================

enum class NodeType {
    UNKNOWN, DOCUMENT, HEAD, BODY, HEADER, NAV, MAIN, ARTICLE, SECTION, DIV,
    PARAGRAPH, HEADING, IMAGE, FIGURE, FIGCAPTION, LINK, LIST, LIST_ITEM,
    ASIDE, FOOTER, BLOCKQUOTE
};

enum class NodeClassification {
    UNKNOWN, DISCARD_BOILERPLATE, DISCARD_AD, DISCARD_RELATED,
    TITLE, SUBTITLE, AUTHOR, DATE, SECTION_HEADING, PULL_QUOTE,
    LEAD_IMAGE, INLINE_IMAGE, BODY_PARAGRAPH, LIST_BLOCK
};

struct PageNode {
    int id = -1;
    NodeType type = NodeType::UNKNOWN;
    int depth = 0;
    int parent = -1;
    std::string tag;
    std::string role;
    std::string className;
    std::string idAttr;
    std::string text;
    int textLength = 0;
    int linkCount = 0;
    int linkTextLength = 0;
    int imageCount = 0;
    float linkDensity = 0.0f;
    float textDensity = 0.0f;
    float contentScore = 0.0f;
    bool isGarbage = false;
    std::vector<int> children;
    std::map<std::string, std::string> attributes;
};

struct PageMetadata {
    std::string title;
    std::string description;
    std::string canonicalUrl;
    std::string author;
    std::string publishDate;
    std::string language;
    std::string siteName;
    std::string ogTitle;
    std::string ogDescription;
    std::string ogImage;
    std::string ogType;
    std::string schemaType;
    std::string jsonLd;
    std::map<std::string, std::string> openGraph;
};

struct ImageCandidate {
    std::string src;
    std::string alt;
    std::string caption;
    int width = 0;
    int height = 0;
    int nodeId = -1;
    float relevanceScore = 0.0f;
    bool isLead = false;
};

struct ArticleCandidate {
    int candidateId = 0;
    int rootNodeId = -1;
    float score = 0.0f;
    int nodeCount = 0;
    int textLength = 0;
    int paragraphCount = 0;
    int imageCount = 0;
    int linkCount = 0;
    float linkDensity = 0.0f;
    std::string previewText;
    std::vector<int> memberNodeIds;
};

struct ClassifiedNode {
    int nodeId = -1;
    NodeClassification classification = NodeClassification::UNKNOWN;
    std::string text;
    std::string imageUrl;
    std::string caption;
    int headingLevel = 2;
    std::vector<std::string> listItems;
    float confidence = 0.0f;
};

struct PageSkeleton {
    std::string url;
    std::string canonicalUrl;
    PageMetadata metadata;
    std::vector<PageNode> nodes;
    std::vector<ImageCandidate> images;
    std::vector<ArticleCandidate> candidates;

    json toJson() const {
        json j;
        j["url"] = url;
        j["canonicalUrl"] = canonicalUrl;
        j["metadata"] = json::object();
        j["metadata"]["title"] = metadata.title;
        j["metadata"]["description"] = metadata.description;
        j["metadata"]["canonicalUrl"] = metadata.canonicalUrl;
        j["metadata"]["author"] = metadata.author;
        j["metadata"]["publishDate"] = metadata.publishDate;
        j["metadata"]["language"] = metadata.language;
        j["metadata"]["siteName"] = metadata.siteName;
        j["metadata"]["ogTitle"] = metadata.ogTitle;
        j["metadata"]["ogDescription"] = metadata.ogDescription;
        j["metadata"]["ogImage"] = metadata.ogImage;
        j["metadata"]["ogType"] = metadata.ogType;
        j["metadata"]["schemaType"] = metadata.schemaType;
        j["metadata"]["jsonLd"] = metadata.jsonLd;
        j["metadata"]["openGraph"] = metadata.openGraph;

        j["nodes"] = json::array();
        for (const auto& n : nodes) {
            json nj;
            nj["id"] = n.id;
            nj["type"] = static_cast<int>(n.type);
            nj["depth"] = n.depth;
            nj["parent"] = n.parent;
            nj["tag"] = n.tag;
            nj["role"] = n.role;
            nj["className"] = n.className;
            nj["idAttr"] = n.idAttr;
            nj["text"] = n.text;
            nj["textLength"] = n.textLength;
            nj["linkCount"] = n.linkCount;
            nj["linkTextLength"] = n.linkTextLength;
            nj["imageCount"] = n.imageCount;
            nj["linkDensity"] = n.linkDensity;
            nj["textDensity"] = n.textDensity;
            nj["contentScore"] = n.contentScore;
            nj["isGarbage"] = n.isGarbage;
            nj["children"] = n.children;
            nj["attributes"] = n.attributes;
            j["nodes"].push_back(nj);
        }

        j["images"] = json::array();
        for (const auto& img : images) {
            json ij;
            ij["src"] = img.src;
            ij["alt"] = img.alt;
            ij["caption"] = img.caption;
            ij["width"] = img.width;
            ij["height"] = img.height;
            ij["nodeId"] = img.nodeId;
            ij["relevanceScore"] = img.relevanceScore;
            ij["isLead"] = img.isLead;
            j["images"].push_back(ij);
        }

        j["candidates"] = json::array();
        for (const auto& c : candidates) {
            json cj;
            cj["candidateId"] = c.candidateId;
            cj["rootNodeId"] = c.rootNodeId;
            cj["score"] = c.score;
            cj["nodeCount"] = c.nodeCount;
            cj["textLength"] = c.textLength;
            cj["paragraphCount"] = c.paragraphCount;
            cj["imageCount"] = c.imageCount;
            cj["linkCount"] = c.linkCount;
            cj["linkDensity"] = c.linkDensity;
            cj["previewText"] = c.previewText;
            cj["memberNodeIds"] = c.memberNodeIds;
            j["candidates"].push_back(cj);
        }
        return j;
    }
};

class PageScanner {
public:
    PageSkeleton scanHtml(const std::string& html, const std::string& url) {
        PageSkeleton skeleton;
        skeleton.url = url;
        skeleton.canonicalUrl = url;

        HtmlParser parser;
        std::vector<RawHtmlNode> rawNodes = parser.parse(html);

        pass1_BuildStructure(rawNodes, skeleton);
        pass2_ExtractMetadata(rawNodes, skeleton);
        pass3_CalculateSignals(skeleton);
        pass4_FilterGarbage(skeleton);
        pass5_DetectCandidates(skeleton);
        collectImages(skeleton, skeleton.images);

        return skeleton;
    }

private:
    NodeType mapTagToNodeType(const std::string& tag) const {
        if (tag == "document") return NodeType::DOCUMENT;
        if (tag == "head") return NodeType::HEAD;
        if (tag == "body") return NodeType::BODY;
        if (tag == "header") return NodeType::HEADER;
        if (tag == "nav") return NodeType::NAV;
        if (tag == "main") return NodeType::MAIN;
        if (tag == "article") return NodeType::ARTICLE;
        if (tag == "section") return NodeType::SECTION;
        if (tag == "div") return NodeType::DIV;
        if (tag == "p") return NodeType::PARAGRAPH;
        if (tag == "h1" || tag == "h2" || tag == "h3" ||
            tag == "h4" || tag == "h5" || tag == "h6") return NodeType::HEADING;
        if (tag == "img") return NodeType::IMAGE;
        if (tag == "figure") return NodeType::FIGURE;
        if (tag == "figcaption") return NodeType::FIGCAPTION;
        if (tag == "a") return NodeType::LINK;
        if (tag == "ul" || tag == "ol") return NodeType::LIST;
        if (tag == "li") return NodeType::LIST_ITEM;
        if (tag == "aside") return NodeType::ASIDE;
        if (tag == "footer") return NodeType::FOOTER;
        if (tag == "blockquote") return NodeType::BLOCKQUOTE;
        return NodeType::UNKNOWN;
    }

    // Pass 1: Build semantic skeleton
    void pass1_BuildStructure(const std::vector<RawHtmlNode>& rawNodes, PageSkeleton& skeleton) {
        if (rawNodes.empty()) return;

        skeleton.nodes.clear();
        skeleton.nodes.reserve(rawNodes.size());

        std::vector<int> rawToPage(rawNodes.size(), -1);

        auto shouldKeepNode = [&](const RawHtmlNode& raw) -> bool {
            if (raw.tag == "document" || raw.tag == "html" || raw.tag == "head" ||
                raw.tag == "body" || raw.tag == "main" || raw.tag == "article" ||
                raw.tag == "section" || raw.tag == "header" || raw.tag == "footer" ||
                raw.tag == "nav" || raw.tag == "aside" || raw.tag == "figure" ||
                raw.tag == "figcaption" || raw.tag == "blockquote") {
                return true;
            }
            if (raw.tag == "p" || raw.tag == "h1" || raw.tag == "h2" ||
                raw.tag == "h3" || raw.tag == "h4" || raw.tag == "h5" || raw.tag == "h6") {
                return true;
            }
            if (raw.tag == "img") {
                std::string src = raw.getAttribute("src");
                if (src.empty()) src = raw.getAttribute("data-src");
                return !src.empty();
            }
            if (raw.tag == "a") {
                return !raw.text.empty() || raw.hasAttribute("href");
            }
            if (raw.tag == "ul" || raw.tag == "ol" || raw.tag == "li") {
                return true;
            }
            if (raw.tag == "div") {
                return !raw.text.empty() || raw.hasAttribute("class") ||
                       raw.hasAttribute("id") || raw.childrenIds.size() > 1;
            }
            return !raw.text.empty();
        };

        for (size_t i = 0; i < rawNodes.size(); ++i) {
            const auto& raw = rawNodes[i];
            if (!shouldKeepNode(raw)) continue;

            PageNode pn;
            pn.id = static_cast<int>(skeleton.nodes.size());
            rawToPage[i] = pn.id;

            pn.tag = raw.tag;
            pn.type = mapTagToNodeType(raw.tag);
            pn.className = raw.getAttribute("class");
            pn.idAttr = raw.getAttribute("id");
            pn.role = raw.getAttribute("role");
            pn.text = raw.text;
            pn.textLength = static_cast<int>(pn.text.length());
            pn.attributes = raw.attributes;

            skeleton.nodes.push_back(pn);
        }

        // Connect parents and children and calculate depth
        for (size_t i = 0; i < rawNodes.size(); ++i) {
            int pageId = rawToPage[i];
            if (pageId < 0) continue;

            int rawParent = rawNodes[i].parentId;
            while (rawParent >= 0 && rawToPage[rawParent] < 0) {
                rawParent = rawNodes[rawParent].parentId;
            }

            if (rawParent >= 0 && rawToPage[rawParent] >= 0) {
                int parentPageId = rawToPage[rawParent];
                skeleton.nodes[pageId].parent = parentPageId;
                skeleton.nodes[parentPageId].children.push_back(pageId);
                skeleton.nodes[pageId].depth = skeleton.nodes[parentPageId].depth + 1;
            } else {
                skeleton.nodes[pageId].parent = -1;
                skeleton.nodes[pageId].depth = 0;
            }
        }
    }

    // Pass 2: Extract metadata
    void pass2_ExtractMetadata(const std::vector<RawHtmlNode>& rawNodes, PageSkeleton& skeleton) {
        PageMetadata& meta = skeleton.metadata;

        for (const auto& raw : rawNodes) {
            if (raw.tag == "html") {
                if (raw.hasAttribute("lang")) meta.language = raw.getAttribute("lang");
            } else if (raw.tag == "title") {
                if (meta.title.empty()) meta.title = raw.text;
            } else if (raw.tag == "meta") {
                std::string name = HtmlParser::toLower(raw.getAttribute("name"));
                std::string prop = HtmlParser::toLower(raw.getAttribute("property"));
                std::string content = raw.getAttribute("content");
                if (content.empty()) continue;

                if (name == "description") meta.description = content;
                else if (name == "author") meta.author = content;
                else if (name == "publish-date" || name == "pubdate" || name == "date") meta.publishDate = content;

                if (!prop.empty() && prop.rfind("og:", 0) == 0) {
                    meta.openGraph[prop] = content;
                    if (prop == "og:title") meta.ogTitle = content;
                    else if (prop == "og:description") meta.ogDescription = content;
                    else if (prop == "og:image") meta.ogImage = content;
                    else if (prop == "og:type") meta.ogType = content;
                    else if (prop == "og:site_name") meta.siteName = content;
                    else if (prop == "og:url" && skeleton.canonicalUrl.empty()) skeleton.canonicalUrl = content;
                } else if (!prop.empty() && prop.rfind("article:", 0) == 0) {
                    meta.openGraph[prop] = content;
                    if (prop == "article:published_time" || prop == "article:modified_time") {
                        if (meta.publishDate.empty()) meta.publishDate = content;
                    } else if (prop == "article:author" && meta.author.empty()) {
                        meta.author = content;
                    }
                }
            } else if (raw.tag == "link") {
                std::string rel = HtmlParser::toLower(raw.getAttribute("rel"));
                std::string href = raw.getAttribute("href");
                if (rel == "canonical") {
                    meta.canonicalUrl = href;
                    skeleton.canonicalUrl = href;
                }
            } else if (raw.tag == "script") {
                std::string type = HtmlParser::toLower(raw.getAttribute("type"));
                if (type.find("ld+json") != std::string::npos && !raw.text.empty()) {
                    meta.jsonLd = raw.text;
                    try {
                        auto jLd = json::parse(raw.text);
                        if (jLd.is_object()) {
                            if (jLd.contains("@type") && jLd["@type"].is_string()) {
                                meta.schemaType = jLd["@type"].get<std::string>();
                            }
                            if (meta.title.empty() && jLd.contains("headline") && jLd["headline"].is_string()) {
                                meta.title = jLd["headline"].get<std::string>();
                            }
                            if (meta.author.empty() && jLd.contains("author")) {
                                if (jLd["author"].is_object() && jLd["author"].contains("name")) {
                                    meta.author = jLd["author"]["name"].get<std::string>();
                                } else if (jLd["author"].is_string()) {
                                    meta.author = jLd["author"].get<std::string>();
                                }
                            }
                            if (meta.publishDate.empty() && jLd.contains("datePublished") && jLd["datePublished"].is_string()) {
                                meta.publishDate = jLd["datePublished"].get<std::string>();
                            }
                            if (meta.ogImage.empty() && jLd.contains("image")) {
                                if (jLd["image"].is_string()) {
                                    meta.ogImage = jLd["image"].get<std::string>();
                                } else if (jLd["image"].is_object() && jLd["image"].contains("url")) {
                                    meta.ogImage = jLd["image"]["url"].get<std::string>();
                                }
                            }
                        }
                    } catch (...) {}
                }
            }
        }

        if (meta.title.empty() && !meta.ogTitle.empty()) meta.title = meta.ogTitle;
        if (meta.description.empty() && !meta.ogDescription.empty()) meta.description = meta.ogDescription;
    }

    // Pass 3: Calculate signals
    void pass3_CalculateSignals(PageSkeleton& skeleton) {
        if (skeleton.nodes.empty()) return;

        std::vector<int> postOrder;
        postOrder.reserve(skeleton.nodes.size());

        std::vector<bool> visited(skeleton.nodes.size(), false);
        std::vector<int> stack;
        stack.push_back(0);

        while (!stack.empty()) {
            int curr = stack.back();
            if (visited[curr]) {
                postOrder.push_back(curr);
                stack.pop_back();
            } else {
                visited[curr] = true;
                for (auto it = skeleton.nodes[curr].children.rbegin(); it != skeleton.nodes[curr].children.rend(); ++it) {
                    stack.push_back(*it);
                }
            }
        }

        for (int id : postOrder) {
            auto& node = skeleton.nodes[id];

            int subTextLen = static_cast<int>(node.text.length());
            int subLinkCount = (node.type == NodeType::LINK) ? 1 : 0;
            int subLinkTextLen = (node.type == NodeType::LINK) ? static_cast<int>(node.text.length()) : 0;
            int subImgCount = (node.type == NodeType::IMAGE) ? 1 : 0;

            for (int childId : node.children) {
                const auto& child = skeleton.nodes[childId];
                subTextLen += child.textLength;
                subLinkCount += child.linkCount;
                subLinkTextLen += child.linkTextLength;
                subImgCount += child.imageCount;
            }

            node.textLength = subTextLen;
            node.linkCount = subLinkCount;
            node.linkTextLength = subLinkTextLen;
            node.imageCount = subImgCount;

            if (node.textLength > 0) {
                node.linkDensity = static_cast<float>(node.linkTextLength) / static_cast<float>(node.textLength);
            } else {
                node.linkDensity = (node.linkCount > 0) ? 1.0f : 0.0f;
            }

            node.textDensity = static_cast<float>(node.textLength) / static_cast<float>(std::max(1, static_cast<int>(node.children.size()) + 1));
        }
    }

    // Pass 4: Garbage filtering
    void pass4_FilterGarbage(PageSkeleton& skeleton) {
        static const std::vector<std::string> kNavKeywords = {
            "nav", "menu", "header", "breadcrumb", "topbar", "navbar", "navigation"
        };
        static const std::vector<std::string> kAdKeywords = {
            "ad", "ads", "advert", "sponsor", "banner", "popup", "commercial", "google-ad", "taboola", "outbrain"
        };
        static const std::vector<std::string> kFooterKeywords = {
            "footer", "copyright", "bottom", "legal", "terms", "policy"
        };
        static const std::vector<std::string> kSocialKeywords = {
            "social", "share", "follow", "twitter", "facebook", "whatsapp", "telegram", "sharer"
        };
        static const std::vector<std::string> kCommentKeywords = {
            "comment", "comments", "disqus", "reply", "feedback", "discuss"
        };
        static const std::vector<std::string> kSidebarKeywords = {
            "sidebar", "aside", "widget", "related", "more-news", "trending", "popular", "recommended"
        };

        auto matchesAny = [](const std::string& target, const std::vector<std::string>& keywords) {
            if (target.empty()) return false;
            std::string lower = HtmlParser::toLower(target);
            for (const auto& kw : keywords) {
                if (lower.find(kw) != std::string::npos) return true;
            }
            return false;
        };

        for (auto& node : skeleton.nodes) {
            std::string combinedClassId = node.className + " " + node.idAttr + " " + node.role;

            if (node.type == NodeType::NAV) { node.isGarbage = true; node.role = "navigation"; continue; }
            if (node.type == NodeType::FOOTER) { node.isGarbage = true; node.role = "footer"; continue; }
            if (node.type == NodeType::ASIDE) { node.isGarbage = true; node.role = "sidebar"; continue; }

            if (node.linkDensity > 0.65f && node.textLength < 400 && node.children.size() > 2) {
                node.isGarbage = true;
                node.role = "navigation";
                continue;
            }

            if (matchesAny(combinedClassId, kAdKeywords)) { node.isGarbage = true; node.role = "advertisement"; }
            else if (matchesAny(combinedClassId, kNavKeywords)) { node.isGarbage = true; node.role = "navigation"; }
            else if (matchesAny(combinedClassId, kFooterKeywords)) { node.isGarbage = true; node.role = "footer"; }
            else if (matchesAny(combinedClassId, kSocialKeywords)) { node.isGarbage = true; node.role = "social"; }
            else if (matchesAny(combinedClassId, kCommentKeywords)) { node.isGarbage = true; node.role = "comments"; }
            else if (matchesAny(combinedClassId, kSidebarKeywords)) { node.isGarbage = true; node.role = "sidebar"; }
        }
    }

    // Pass 5: Detect candidates
    void pass5_DetectCandidates(PageSkeleton& skeleton) {
        skeleton.candidates.clear();

        auto countParagraphsAndMembers = [&](int rootId, int& outPCount, std::vector<int>& outMembers) {
            outPCount = 0;
            outMembers.clear();
            std::vector<int> q;
            q.push_back(rootId);
            size_t idx = 0;
            while (idx < q.size()) {
                int currId = q[idx++];
                if (currId < 0 || currId >= static_cast<int>(skeleton.nodes.size())) continue;
                const auto& node = skeleton.nodes[currId];
                if (node.isGarbage) continue;
                outMembers.push_back(currId);
                if (node.type == NodeType::PARAGRAPH && node.text.length() >= 20) {
                    outPCount++;
                }
                for (int ch : node.children) q.push_back(ch);
            }
        };

        static const std::vector<std::string> kPositiveTokens = {
            "article", "story", "post", "body", "content", "entry", "main-content", "news-body", "article-text"
        };

        for (const auto& node : skeleton.nodes) {
            if (node.isGarbage) continue;
            if (node.type != NodeType::ARTICLE && node.type != NodeType::MAIN &&
                node.type != NodeType::SECTION && node.type != NodeType::DIV) {
                continue;
            }
            if (node.textLength < 150) continue;

            int pCount = 0;
            std::vector<int> members;
            countParagraphsAndMembers(node.id, pCount, members);

            if (pCount < 1 && node.textLength < 300) continue;

            int nonLinkTextLen = std::max(0, node.textLength - node.linkTextLength);
            float score = static_cast<float>(nonLinkTextLen) / 50.0f;
            score += static_cast<float>(pCount) * 8.0f;

            if (node.type == NodeType::ARTICLE) score += 40.0f;
            if (node.type == NodeType::MAIN) score += 30.0f;

            std::string classId = HtmlParser::toLower(node.className + " " + node.idAttr);
            for (const auto& tok : kPositiveTokens) {
                if (classId.find(tok) != std::string::npos) { score += 25.0f; break; }
            }

            if (node.linkDensity > 0.3f) score *= (1.0f - node.linkDensity);

            if (node.depth >= 2 && node.depth <= 7) score += 10.0f;

            if (score > 15.0f) {
                ArticleCandidate cand;
                cand.candidateId = static_cast<int>(skeleton.candidates.size() + 1);
                cand.rootNodeId = node.id;
                cand.score = score;
                cand.nodeCount = static_cast<int>(members.size());
                cand.textLength = node.textLength;
                cand.paragraphCount = pCount;
                cand.imageCount = node.imageCount;
                cand.linkCount = node.linkCount;
                cand.linkDensity = node.linkDensity;
                cand.memberNodeIds = members;

                for (int memId : members) {
                    const auto& memNode = skeleton.nodes[memId];
                    if (memNode.type == NodeType::PARAGRAPH && !memNode.text.empty()) {
                        cand.previewText = memNode.text.substr(0, 200);
                        break;
                    }
                }
                if (cand.previewText.empty() && !node.text.empty()) {
                    cand.previewText = node.text.substr(0, 200);
                }

                skeleton.candidates.push_back(cand);
            }
        }

        std::sort(skeleton.candidates.begin(), skeleton.candidates.end(),
            [](const ArticleCandidate& a, const ArticleCandidate& b) { return a.score > b.score; });

        if (!skeleton.candidates.empty()) {
            skeleton.nodes[skeleton.candidates[0].rootNodeId].role = "article-candidate";
        }
    }

    // Collect images
    void collectImages(const PageSkeleton& skeleton, std::vector<ImageCandidate>& outImages) {
        outImages.clear();

        for (const auto& node : skeleton.nodes) {
            if (node.type == NodeType::IMAGE) {
                std::string src = node.attributes.count("src") ? node.attributes.at("src") : "";
                if (src.empty() && node.attributes.count("data-src")) src = node.attributes.at("data-src");
                if (src.empty() && node.attributes.count("data-original")) src = node.attributes.at("data-original");

                if (src.empty() || src.rfind("data:", 0) == 0) continue;

                ImageCandidate ic;
                ic.src = src;
                ic.alt = node.attributes.count("alt") ? node.attributes.at("alt") : "";
                ic.nodeId = node.id;

                if (node.parent >= 0 && skeleton.nodes[node.parent].type == NodeType::FIGURE) {
                    for (int sibId : skeleton.nodes[node.parent].children) {
                        if (skeleton.nodes[sibId].type == NodeType::FIGCAPTION) {
                            ic.caption = skeleton.nodes[sibId].text;
                            break;
                        }
                    }
                }
                if (ic.caption.empty() && node.attributes.count("title")) {
                    ic.caption = node.attributes.at("title");
                }

                if (node.attributes.count("width")) {
                    try { ic.width = std::stoi(node.attributes.at("width")); } catch (...) {}
                }
                if (node.attributes.count("height")) {
                    try { ic.height = std::stoi(node.attributes.at("height")); } catch (...) {}
                }

                if (ic.width > 0 && ic.width < 100 && ic.height > 0 && ic.height < 100) continue;

                outImages.push_back(ic);
            }
        }

        if (!outImages.empty()) {
            bool matchedOg = false;
            if (!skeleton.metadata.ogImage.empty()) {
                for (auto& img : outImages) {
                    if (img.src.find(skeleton.metadata.ogImage) != std::string::npos ||
                        skeleton.metadata.ogImage.find(img.src) != std::string::npos) {
                        img.isLead = true;
                        matchedOg = true;
                        break;
                    }
                }
            }
            if (!matchedOg && !outImages.empty()) {
                outImages[0].isLead = true;
            }
        }
    }
};

// ============================================================================
// Article Brain (classification)
// ============================================================================

class ArticleBrain {
public:
    std::vector<ClassifiedNode> classifyCandidateNodes(
        const PageSkeleton& skeleton,
        const ArticleCandidate& candidate
    ) {
        std::vector<ClassifiedNode> result;
        result.reserve(candidate.memberNodeIds.size());

        int totalNodes = static_cast<int>(candidate.memberNodeIds.size());
        for (int i = 0; i < totalNodes; ++i) {
            int memId = candidate.memberNodeIds[i];
            if (memId < 0 || memId >= static_cast<int>(skeleton.nodes.size())) continue;

            const auto& node = skeleton.nodes[memId];
            ClassifiedNode cn = evaluateNode(node, i, totalNodes, skeleton, candidate);
            if (cn.classification != NodeClassification::UNKNOWN) {
                result.push_back(cn);
            }
        }

        refineClassifications(result, skeleton);
        return result;
    }

private:
    ClassifiedNode evaluateNode(
        const PageNode& node,
        int nodeIndexInCandidate,
        int totalCandidateNodes,
        const PageSkeleton& skeleton,
        const ArticleCandidate& candidate
    ) {
        ClassifiedNode cn;
        cn.nodeId = node.id;
        cn.text = node.text;

        if (node.isGarbage) {
            cn.classification = NodeClassification::DISCARD_BOILERPLATE;
            return cn;
        }

        std::string classId = HtmlParser::toLower(node.className + " " + node.idAttr + " " + node.role);

        if (classId.find("sponsored") != std::string::npos ||
            classId.find("promo") != std::string::npos ||
            classId.find("advert") != std::string::npos) {
            cn.classification = NodeClassification::DISCARD_AD;
            return cn;
        }

        if (classId.find("related") != std::string::npos ||
            classId.find("read-more") != std::string::npos) {
            cn.classification = NodeClassification::DISCARD_RELATED;
            return cn;
        }

        // Title
        if (node.tag == "h1" || classId.find("article-title") != std::string::npos ||
            classId.find("headline") != std::string::npos) {
            cn.classification = NodeClassification::TITLE;
            cn.confidence = 0.95f;
            return cn;
        }

        // Author/Byline
        if (classId.find("author") != std::string::npos ||
            classId.find("byline") != std::string::npos ||
            classId.find("writer") != std::string::npos) {
            if (node.text.length() > 0 && node.text.length() < 100) {
                cn.classification = NodeClassification::AUTHOR;
                cn.confidence = 0.90f;
                return cn;
            }
        }
        // Arabic author markers
        if (node.text.rfind("كتب:", 0) == 0 || node.text.rfind("بقلم:", 0) == 0 ||
            node.text.rfind("متابعة:", 0) == 0 || node.text.rfind("By ", 0) == 0) {
            if (node.text.length() < 80) {
                cn.classification = NodeClassification::AUTHOR;
                cn.confidence = 0.88f;
                return cn;
            }
        }

        // Date
        if (node.tag == "time" || classId.find("date") != std::string::npos ||
            classId.find("time") != std::string::npos || classId.find("publish") != std::string::npos) {
            if (node.text.length() > 0 && node.text.length() < 80) {
                cn.classification = NodeClassification::DATE;
                cn.confidence = 0.88f;
                return cn;
            }
        }

        // Headings
        if (node.type == NodeType::HEADING) {
            cn.classification = NodeClassification::SECTION_HEADING;
            cn.headingLevel = 2;
            if (node.tag == "h3") cn.headingLevel = 3;
            else if (node.tag == "h4") cn.headingLevel = 4;
            cn.confidence = 0.85f;
            return cn;
        }

        // Blockquote
        if (node.type == NodeType::BLOCKQUOTE || classId.find("quote") != std::string::npos) {
            if (!node.text.empty()) {
                cn.classification = NodeClassification::PULL_QUOTE;
                cn.confidence = 0.85f;
                return cn;
            }
        }

        // Image
        if (node.type == NodeType::IMAGE) {
            std::string src = node.attributes.count("src") ? node.attributes.at("src") : "";
            if (src.empty() && node.attributes.count("data-src")) src = node.attributes.at("data-src");

            if (!src.empty() && src.rfind("data:", 0) != 0) {
                cn.imageUrl = src;
                cn.caption = node.attributes.count("alt") ? node.attributes.at("alt") : "";

                if (node.parent >= 0 && skeleton.nodes[node.parent].type == NodeType::FIGURE) {
                    for (int ch : skeleton.nodes[node.parent].children) {
                        if (skeleton.nodes[ch].type == NodeType::FIGCAPTION) {
                            cn.caption = skeleton.nodes[ch].text;
                            break;
                        }
                    }
                }

                cn.classification = (nodeIndexInCandidate < 3) ? NodeClassification::LEAD_IMAGE : NodeClassification::INLINE_IMAGE;
                cn.confidence = 0.85f;
                return cn;
            }
        }

        // Paragraph
        if (node.type == NodeType::PARAGRAPH) {
            if (node.linkDensity > 0.5f) {
                cn.classification = NodeClassification::DISCARD_RELATED;
                return cn;
            }

            if (nodeIndexInCandidate <= 2 && (classId.find("sub") != std::string::npos ||
                classId.find("lead") != std::string::npos || classId.find("summary") != std::string::npos)) {
                cn.classification = NodeClassification::SUBTITLE;
                cn.confidence = 0.88f;
                return cn;
            }

            if (node.text.length() >= 15) {
                cn.classification = NodeClassification::BODY_PARAGRAPH;
                cn.confidence = 0.90f;
                return cn;
            }
        }

        // List
        if (node.type == NodeType::LIST) {
            std::vector<std::string> items;
            for (int ch : node.children) {
                if (skeleton.nodes[ch].type == NodeType::LIST_ITEM && !skeleton.nodes[ch].text.empty()) {
                    items.push_back(skeleton.nodes[ch].text);
                }
            }
            if (!items.empty()) {
                cn.classification = NodeClassification::LIST_BLOCK;
                cn.listItems = items;
                cn.confidence = 0.80f;
                return cn;
            }
        }

        return cn;
    }

    void refineClassifications(
        std::vector<ClassifiedNode>& classified,
        const PageSkeleton& skeleton
    ) {
        bool hasTitle = false;
        bool hasLeadImage = false;

        for (auto& cn : classified) {
            if (cn.classification == NodeClassification::TITLE) {
                if (!hasTitle) { hasTitle = true; }
                else { cn.classification = NodeClassification::SECTION_HEADING; cn.headingLevel = 2; }
            } else if (cn.classification == NodeClassification::LEAD_IMAGE) {
                if (!hasLeadImage) { hasLeadImage = true; }
                else { cn.classification = NodeClassification::INLINE_IMAGE; }
            }
        }

        if (!hasLeadImage && !skeleton.images.empty()) {
            for (auto& cn : classified) {
                if (cn.classification == NodeClassification::INLINE_IMAGE) {
                    cn.classification = NodeClassification::LEAD_IMAGE;
                    break;
                }
            }
        }
    }
};

// ============================================================================
// Article Rebuilder
// ============================================================================

struct ArticleBlock {
    enum BlockType { PARAGRAPH, HEADING, SUBTITLE, IMAGE, QUOTE, LIST } type;
    std::string text;
    int headingLevel = 2;
    std::string imageUrl;
    std::string caption;
    std::string alt;
    std::vector<std::string> listItems;
};

struct NewsArticle {
    std::string url;
    std::string canonicalUrl;
    std::string title;
    std::string subtitle;
    std::string author;
    std::string publishDate;
    std::string language;
    std::string siteName;
    std::string leadImageUrl;
    std::string leadImageCaption;
    std::vector<ArticleBlock> blocks;
    std::string plainText;
    int wordCount = 0;
    int readingTimeMinutes = 1;
    float confidenceScore = 0.0f;

    json toJson() const {
        json j;
        j["url"] = url;
        j["canonicalUrl"] = canonicalUrl;
        j["title"] = title;
        j["subtitle"] = subtitle;
        j["author"] = author;
        j["publishDate"] = publishDate;
        j["language"] = language;
        j["siteName"] = siteName;
        j["leadImageUrl"] = leadImageUrl;
        j["leadImageCaption"] = leadImageCaption;
        j["blocks"] = json::array();
        for (const auto& b : blocks) {
            json bj;
            bj["type"] = b.type;
            bj["text"] = b.text;
            bj["headingLevel"] = b.headingLevel;
            bj["imageUrl"] = b.imageUrl;
            bj["caption"] = b.caption;
            bj["alt"] = b.alt;
            bj["listItems"] = b.listItems;
            j["blocks"].push_back(bj);
        }
        j["plainText"] = plainText;
        j["wordCount"] = wordCount;
        j["readingTimeMinutes"] = readingTimeMinutes;
        j["confidenceScore"] = confidenceScore;
        return j;
    }
};

class ArticleRebuilder {
public:
    int calculateWordCount(const std::string& text) const {
        if (text.empty()) return 0;
        int count = 0;
        bool inWord = false;
        for (unsigned char c : text) {
            if (std::isspace(c)) { inWord = false; }
            else { if (!inWord) { count++; inWord = true; } }
        }
        return count;
    }

    int estimateReadingTime(int wordCount) const {
        int minutes = wordCount / 180;
        return (minutes < 1) ? 1 : minutes;
    }

    NewsArticle rebuild(
        const PageSkeleton& skeleton,
        const std::vector<ClassifiedNode>& classifiedNodes
    ) {
        NewsArticle article;
        article.url = skeleton.url;
        article.canonicalUrl = skeleton.canonicalUrl;
        article.language = skeleton.metadata.language;
        article.siteName = skeleton.metadata.siteName;

        article.title = skeleton.metadata.title;
        article.author = skeleton.metadata.author;
        article.publishDate = skeleton.metadata.publishDate;
        article.leadImageUrl = skeleton.metadata.ogImage;

        std::stringstream fullTextSs;

        for (const auto& cn : classifiedNodes) {
            switch (cn.classification) {
                case NodeClassification::TITLE:
                    if (!cn.text.empty()) article.title = cn.text;
                    break;
                case NodeClassification::SUBTITLE:
                    if (article.subtitle.empty() && !cn.text.empty()) {
                        article.subtitle = cn.text;
                        ArticleBlock blk; blk.type = ArticleBlock::SUBTITLE; blk.text = cn.text;
                        article.blocks.push_back(blk);
                        fullTextSs << cn.text << "\n\n";
                    }
                    break;
                case NodeClassification::AUTHOR:
                    if (!cn.text.empty()) article.author = cn.text;
                    break;
                case NodeClassification::DATE:
                    if (!cn.text.empty()) article.publishDate = cn.text;
                    break;
                case NodeClassification::LEAD_IMAGE:
                    if (!cn.imageUrl.empty()) {
                        article.leadImageUrl = cn.imageUrl;
                        article.leadImageCaption = cn.caption;
                    }
                    break;
                case NodeClassification::INLINE_IMAGE:
                    if (!cn.imageUrl.empty()) {
                        ArticleBlock blk; blk.type = ArticleBlock::IMAGE; blk.imageUrl = cn.imageUrl; blk.caption = cn.caption;
                        article.blocks.push_back(blk);
                    }
                    break;
                case NodeClassification::BODY_PARAGRAPH:
                    if (!cn.text.empty()) {
                        ArticleBlock blk; blk.type = ArticleBlock::PARAGRAPH; blk.text = cn.text;
                        article.blocks.push_back(blk);
                        fullTextSs << cn.text << "\n\n";
                    }
                    break;
                case NodeClassification::SECTION_HEADING:
                    if (!cn.text.empty()) {
                        ArticleBlock blk; blk.type = ArticleBlock::HEADING; blk.headingLevel = cn.headingLevel; blk.text = cn.text;
                        article.blocks.push_back(blk);
                        fullTextSs << cn.text << "\n\n";
                    }
                    break;
                case NodeClassification::PULL_QUOTE:
                    if (!cn.text.empty()) {
                        ArticleBlock blk; blk.type = ArticleBlock::QUOTE; blk.text = cn.text;
                        article.blocks.push_back(blk);
                        fullTextSs << "\"" << cn.text << "\"\n\n";
                    }
                    break;
                case NodeClassification::LIST_BLOCK:
                    if (!cn.listItems.empty()) {
                        ArticleBlock blk; blk.type = ArticleBlock::LIST; blk.listItems = cn.listItems;
                        article.blocks.push_back(blk);
                        for (const auto& item : cn.listItems) fullTextSs << "• " << item << "\n";
                        fullTextSs << "\n";
                    }
                    break;
                default: break;
            }
        }

        if (article.subtitle.empty() && !skeleton.metadata.description.empty()) {
            article.subtitle = skeleton.metadata.description;
        }
        if (article.leadImageUrl.empty() && !skeleton.images.empty()) {
            article.leadImageUrl = skeleton.images[0].src;
            article.leadImageCaption = skeleton.images[0].caption;
        }

        article.plainText = fullTextSs.str();
        article.wordCount = calculateWordCount(article.plainText);
        article.readingTimeMinutes = estimateReadingTime(article.wordCount);

        float score = 0.5f;
        if (!article.title.empty()) score += 0.2f;
        if (article.blocks.size() >= 3) score += 0.2f;
        if (!article.leadImageUrl.empty()) score += 0.1f;
        article.confidenceScore = std::min(1.0f, score);

        return article;
    }
};

// ============================================================================
// HTTP Fetcher (cross-platform)
// ============================================================================

class HttpFetcher {
public:
    static std::string fetch(const std::string& url) {
#if defined(_WIN32)
        return fetchWinHttp(url);
#elif defined(__ANDROID__) || defined(__linux__)
        return fetchCurl(url);
#else
        return "";
#endif
    }

private:
#if defined(_WIN32)
    static std::string fetchWinHttp(const std::string& url) {
        std::string response;
        URL_COMPONENTS urlComp;
        ZeroMemory(&urlComp, sizeof(urlComp));
        urlComp.dwStructSize = sizeof(urlComp);

        wchar_t hostName[256] = {0};
        wchar_t urlPath[2048] = {0};
        urlComp.lpszHostName = hostName;
        urlComp.dwHostNameLength = sizeof(hostName) / sizeof(wchar_t);
        urlComp.lpszUrlPath = urlPath;
        urlComp.dwUrlPathLength = sizeof(urlPath) / sizeof(wchar_t);

        int wideLen = MultiByteToWideChar(CP_UTF8, 0, url.c_str(), -1, nullptr, 0);
        if (wideLen <= 0) return "";
        std::vector<wchar_t> wUrl(wideLen);
        MultiByteToWideChar(CP_UTF8, 0, url.c_str(), -1, wUrl.data(), wideLen);

        if (!WinHttpCrackUrl(wUrl.data(), 0, 0, &urlComp)) return "";

        HINTERNET hSession = WinHttpOpen(
            L"YallaNews/1.0", WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
            WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
        if (!hSession) return "";

        WinHttpSetTimeouts(hSession, 5000, 5000, 10000, 10000);

        INTERNET_PORT port = urlComp.nPort;
        HINTERNET hConnect = WinHttpConnect(hSession, urlComp.lpszHostName, port, 0);
        if (!hConnect) { WinHttpCloseHandle(hSession); return ""; }

        DWORD flags = (urlComp.nScheme == INTERNET_SCHEME_HTTPS) ? WINHTTP_FLAG_SECURE : 0;
        HINTERNET hRequest = WinHttpOpenRequest(
            hConnect, L"GET", urlComp.lpszUrlPath, nullptr,
            WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, flags);

        if (!hRequest) { WinHttpCloseHandle(hConnect); WinHttpCloseHandle(hSession); return ""; }

        DWORD redirectOption = WINHTTP_OPTION_REDIRECT_POLICY_ALWAYS;
        WinHttpSetOption(hRequest, WINHTTP_OPTION_REDIRECT_POLICY, &redirectOption, sizeof(redirectOption));

        LPCWSTR headers = L"User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36\r\nAccept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8\r\nAccept-Language: ar,en-US,en;q=0.9\r\n";
        WinHttpAddRequestHeaders(hRequest, headers, -1L, WINHTTP_ADDREQ_FLAG_ADD | WINHTTP_ADDREQ_FLAG_REPLACE);

        BOOL bResults = WinHttpSendRequest(hRequest, WINHTTP_NO_ADDITIONAL_HEADERS, 0,
            WINHTTP_NO_REQUEST_DATA, 0, 0, 0);

        if (bResults) bResults = WinHttpReceiveResponse(hRequest, nullptr);

        if (bResults) {
            DWORD dwSize = 0;
            std::vector<char> buffer;
            do {
                dwSize = 0;
                if (!WinHttpQueryDataAvailable(hRequest, &dwSize)) break;
                if (dwSize == 0) break;
                size_t currentSize = buffer.size();
                buffer.resize(currentSize + dwSize);
                DWORD dwDownloaded = 0;
                if (WinHttpReadData(hRequest, buffer.data() + currentSize, dwSize, &dwDownloaded)) {
                    buffer.resize(currentSize + dwDownloaded);
                } else break;
            } while (dwSize > 0);
            if (!buffer.empty()) response.assign(buffer.begin(), buffer.end());
        }

        WinHttpCloseHandle(hRequest);
        WinHttpCloseHandle(hConnect);
        WinHttpCloseHandle(hSession);
        return response;
    }
#elif defined(__ANDROID__) || defined(__linux__)
    static size_t writeCallback(void* contents, size_t size, size_t nmemb, std::string* s) {
        size_t newLength = size * nmemb;
        try { s->append(static_cast<char*>(contents), newLength); }
        catch (...) { return 0; }
        return newLength;
    }

    static std::string fetchCurl(const std::string& url) {
        CURL* curl = curl_easy_init();
        if (!curl) return "";
        std::string response;
        curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
        curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, writeCallback);
        curl_easy_setopt(curl, CURLOPT_WRITEDATA, &response);
        curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
        curl_easy_setopt(curl, CURLOPT_TIMEOUT, 10L);
        curl_easy_setopt(curl, CURLOPT_USERAGENT, "YallaNews/1.0");
        curl_easy_setopt(curl, CURLOPT_ACCEPT_ENCODING, "");
        CURLcode res = curl_easy_perform(curl);
        curl_easy_cleanup(curl);
        return (res == CURLE_OK) ? response : "";
    }
#endif
};

// ============================================================================
// RSS/Atom Parser
// ============================================================================

std::vector<std::string> parseRssFeed(const std::string& xml) {
    std::vector<std::string> urls;
    std::regex itemRegex("<item>.*?</item>", std::regex::icase | std::regex::optimize);
    std::regex linkRegex("<link[^>]*>([^<]+)</link>", std::regex::icase);

    auto itemsBegin = std::sregex_iterator(xml.begin(), xml.end(), itemRegex);
    auto itemsEnd = std::sregex_iterator();

    for (std::sregex_iterator i = itemsBegin; i != itemsEnd; ++i) {
        std::string item = i->str();
        std::smatch linkMatch;
        if (std::regex_search(item, linkMatch, linkRegex)) {
            std::string link = linkMatch[1].str();
            link.erase(0, link.find_first_not_of(" \t\n\r"));
            link.erase(link.find_last_not_of(" \t\n\r") + 1);
            if (!link.empty() && (link.rfind("http://", 0) == 0 || link.rfind("https://", 0) == 0)) {
                urls.push_back(link);
            }
        }
    }
    return urls;
}

std::vector<std::string> parseAtomFeed(const std::string& xml) {
    std::vector<std::string> urls;
    std::regex entryRegex("<entry>.*?</entry>", std::regex::icase | std::regex::optimize);
    std::regex linkRegex("<link[^>]*href=\"([^\"]+)\"", std::regex::icase);

    auto entriesBegin = std::sregex_iterator(xml.begin(), xml.end(), entryRegex);
    auto entriesEnd = std::sregex_iterator();

    for (std::sregex_iterator i = entriesBegin; i != entriesEnd; ++i) {
        std::string entry = i->str();
        std::smatch linkMatch;
        if (std::regex_search(entry, linkMatch, linkRegex)) {
            std::string link = linkMatch[1].str();
            if (!link.empty() && (link.rfind("http://", 0) == 0 || link.rfind("https://", 0) == 0)) {
                urls.push_back(link);
            }
        }
    }
    return urls;
}

// ============================================================================
// YallaNewsIngestion Implementation
// ============================================================================

struct YallaNewsIngestion {
    int32_t timeout_ms = 30000;
    int32_t rate_limit_rpm = 60;
    std::chrono::steady_clock::time_point last_request;
    std::mutex rate_mutex;

    std::string fetch_url(const std::string& url) {
        // Rate limiting
        {
            std::lock_guard<std::mutex> lock(rate_mutex);
            auto now = std::chrono::steady_clock::now();
            auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(now - last_request).count();
            int64_t min_interval = 60000 / rate_limit_rpm;
            if (elapsed < min_interval) {
                std::this_thread::sleep_for(std::chrono::milliseconds(min_interval - elapsed));
            }
            last_request = std::chrono::steady_clock::now();
        }

        return HttpFetcher::fetch(url);
    }

    std::vector<std::string> parse_rss(const std::string& xml) {
        return parseRssFeed(xml);
    }

    std::vector<std::string> parse_atom(const std::string& xml) {
        return parseAtomFeed(xml);
    }

    json extract_article(const std::string& html, const std::string& url) {
        PageScanner scanner;
        PageSkeleton skeleton = scanner.scanHtml(html, url);

        ArticleBrain brain;
        std::vector<ClassifiedNode> classifiedNodes;
        if (!skeleton.candidates.empty()) {
            classifiedNodes = brain.classifyCandidateNodes(skeleton, skeleton.candidates[0]);
        }

        ArticleRebuilder rebuilder;
        NewsArticle article = rebuilder.rebuild(skeleton, classifiedNodes);
        return article.toJson();
    }
};

extern "C" {

YALLA_CORE_EXPORT YallaNewsIngestionHandle yalla_news_ingestion_create() {
    return new YallaNewsIngestion();
}

YALLA_CORE_EXPORT void yalla_news_ingestion_destroy(YallaNewsIngestionHandle handle) {
    if (handle) delete static_cast<YallaNewsIngestion*>(handle);
}

YALLA_CORE_EXPORT bool yalla_news_ingestion_fetch_rss(YallaNewsIngestionHandle handle,
    const char* feed_url, YallaCompletionCallback callback, void* user_data) {
    if (!handle || !feed_url) return false;
    auto* ingestion = static_cast<YallaNewsIngestion*>(handle);

    std::thread([ingestion, feed_url, callback, user_data]() {
        std::string xml = ingestion->fetch_url(feed_url);
        std::vector<std::string> urls = ingestion->parse_rss(xml);

        json result;
        result["success"] = true;
        result["articles"] = urls;

        if (callback) callback(true, strdup(result.dump().c_str()), user_data);
    }).detach();

    return true;
}

YALLA_CORE_EXPORT bool yalla_news_ingestion_fetch_atom(YallaNewsIngestionHandle handle,
    const char* feed_url, YallaCompletionCallback callback, void* user_data) {
    if (!handle || !feed_url) return false;
    auto* ingestion = static_cast<YallaNewsIngestion*>(handle);

    std::thread([ingestion, feed_url, callback, user_data]() {
        std::string xml = ingestion->fetch_url(feed_url);
        std::vector<std::string> urls = ingestion->parse_atom(xml);

        json result;
        result["success"] = true;
        result["articles"] = urls;

        if (callback) callback(true, strdup(result.dump().c_str()), user_data);
    }).detach();

    return true;
}

YALLA_CORE_EXPORT bool yalla_news_ingestion_extract_html(YallaNewsIngestionHandle handle,
    const char* url, const char* html, YallaCompletionCallback callback, void* user_data) {
    if (!handle || !url || !html) return false;
    auto* ingestion = static_cast<YallaNewsIngestion*>(handle);

    std::thread([ingestion, url, html, callback, user_data]() {
        json article = ingestion->extract_article(html, url);
        json result;
        result["success"] = true;
        result["article"] = article;

        if (callback) callback(true, strdup(result.dump().c_str()), user_data);
    }).detach();

    return true;
}

YALLA_CORE_EXPORT void yalla_news_ingestion_set_timeout(YallaNewsIngestionHandle handle, int32_t timeout_ms) {
    if (handle) static_cast<YallaNewsIngestion*>(handle)->timeout_ms = timeout_ms;
}

YALLA_CORE_EXPORT void yalla_news_ingestion_set_rate_limit(YallaNewsIngestionHandle handle, int32_t requests_per_minute) {
    if (handle) static_cast<YallaNewsIngestion*>(handle)->rate_limit_rpm = requests_per_minute > 0 ? requests_per_minute : 60;
}

} // extern "C"