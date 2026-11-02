#ifndef PAGE_SKELETON_H
#define PAGE_SKELETON_H

#include <string>
#include <vector>
#include <map>
#include <cstdint>
#include "../../yalla_engine/nlohmann/json.hpp"

namespace newsbrain {

using NodeId = int32_t;

enum class NodeType {
    UNKNOWN = 0,
    DOCUMENT,
    HEAD,
    BODY,
    HEADER,
    NAV,
    MAIN,
    ARTICLE,
    SECTION,
    DIV,
    PARAGRAPH,
    HEADING,
    IMAGE,
    FIGURE,
    FIGCAPTION,
    LINK,
    LIST,
    LIST_ITEM,
    ASIDE,
    FOOTER,
    BLOCKQUOTE,
    ADVERTISEMENT,
    GARBAGE
};

inline std::string nodeTypeToString(NodeType t) {
    switch (t) {
        case NodeType::DOCUMENT: return "DOCUMENT";
        case NodeType::HEAD: return "HEAD";
        case NodeType::BODY: return "BODY";
        case NodeType::HEADER: return "HEADER";
        case NodeType::NAV: return "NAV";
        case NodeType::MAIN: return "MAIN";
        case NodeType::ARTICLE: return "ARTICLE";
        case NodeType::SECTION: return "SECTION";
        case NodeType::DIV: return "DIV";
        case NodeType::PARAGRAPH: return "PARAGRAPH";
        case NodeType::HEADING: return "HEADING";
        case NodeType::IMAGE: return "IMAGE";
        case NodeType::FIGURE: return "FIGURE";
        case NodeType::FIGCAPTION: return "FIGCAPTION";
        case NodeType::LINK: return "LINK";
        case NodeType::LIST: return "LIST";
        case NodeType::LIST_ITEM: return "LIST_ITEM";
        case NodeType::ASIDE: return "ASIDE";
        case NodeType::FOOTER: return "FOOTER";
        case NodeType::BLOCKQUOTE: return "BLOCKQUOTE";
        case NodeType::ADVERTISEMENT: return "ADVERTISEMENT";
        case NodeType::GARBAGE: return "GARBAGE";
        default: return "UNKNOWN";
    }
}

inline NodeType stringToNodeType(const std::string& s) {
    if (s == "DOCUMENT") return NodeType::DOCUMENT;
    if (s == "HEAD") return NodeType::HEAD;
    if (s == "BODY") return NodeType::BODY;
    if (s == "HEADER") return NodeType::HEADER;
    if (s == "NAV") return NodeType::NAV;
    if (s == "MAIN") return NodeType::MAIN;
    if (s == "ARTICLE") return NodeType::ARTICLE;
    if (s == "SECTION") return NodeType::SECTION;
    if (s == "DIV") return NodeType::DIV;
    if (s == "PARAGRAPH") return NodeType::PARAGRAPH;
    if (s == "HEADING") return NodeType::HEADING;
    if (s == "IMAGE") return NodeType::IMAGE;
    if (s == "FIGURE") return NodeType::FIGURE;
    if (s == "FIGCAPTION") return NodeType::FIGCAPTION;
    if (s == "LINK") return NodeType::LINK;
    if (s == "LIST") return NodeType::LIST;
    if (s == "LIST_ITEM") return NodeType::LIST_ITEM;
    if (s == "ASIDE") return NodeType::ASIDE;
    if (s == "FOOTER") return NodeType::FOOTER;
    if (s == "BLOCKQUOTE") return NodeType::BLOCKQUOTE;
    if (s == "ADVERTISEMENT") return NodeType::ADVERTISEMENT;
    if (s == "GARBAGE") return NodeType::GARBAGE;
    return NodeType::UNKNOWN;
}

struct PageNode {
    NodeId id = -1;
    NodeType type = NodeType::UNKNOWN;
    int depth = 0;
    int parent = -1;

    std::string tag;
    std::string role;          // Semantic role: "navigation", "advertisement", "main", "article-candidate", "sidebar", "footer", "content", "header", etc.
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

    std::map<std::string, std::string> attributes;
    std::vector<NodeId> children;
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
    std::string jsonLd;
    std::string schemaType;
    std::map<std::string, std::string> openGraph;
};

struct ImageCandidate {
    std::string src;
    std::string alt;
    std::string caption;
    int width = 0;
    int height = 0;
    NodeId nodeId = -1;
    float relevanceScore = 0.0f;
    bool isLead = false;
};

struct ArticleCandidate {
    int candidateId = 0;
    NodeId rootNodeId = -1;
    float score = 0.0f;
    int nodeCount = 0;
    int textLength = 0;
    int paragraphCount = 0;
    int imageCount = 0;
    int linkCount = 0;
    float linkDensity = 0.0f;
    std::string previewText;
    std::vector<NodeId> memberNodeIds;
};

struct PageSkeleton {
    std::string url;
    std::string canonicalUrl;
    PageMetadata metadata;
    std::vector<PageNode> nodes;
    std::vector<ImageCandidate> images;
    std::vector<ArticleCandidate> candidates;

    // Helper to serialize to JSON
    nlohmann::json toJson() const;
};

} // namespace newsbrain

#endif // PAGE_SKELETON_H
