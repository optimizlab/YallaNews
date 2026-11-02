#ifndef NEWS_ARTICLE_H
#define NEWS_ARTICLE_H

#include <string>
#include <vector>
#include "../../yalla_engine/nlohmann/json.hpp"

namespace newsbrain {

enum class BlockType {
    PARAGRAPH = 0,
    HEADING,
    SUBTITLE,
    IMAGE,
    QUOTE,
    LIST
};

inline std::string blockTypeToString(BlockType t) {
    switch (t) {
        case BlockType::PARAGRAPH: return "PARAGRAPH";
        case BlockType::HEADING: return "HEADING";
        case BlockType::SUBTITLE: return "SUBTITLE";
        case BlockType::IMAGE: return "IMAGE";
        case BlockType::QUOTE: return "QUOTE";
        case BlockType::LIST: return "LIST";
        default: return "PARAGRAPH";
    }
}

struct ArticleBlock {
    BlockType type = BlockType::PARAGRAPH;
    std::string text;
    int headingLevel = 2; // For headings (1, 2, 3...)
    std::string imageUrl;
    std::string caption;
    std::string alt;
    std::vector<std::string> listItems;

    nlohmann::json toJson() const {
        nlohmann::json j;
        j["type"] = blockTypeToString(type);
        j["text"] = text;
        if (type == BlockType::HEADING) {
            j["headingLevel"] = headingLevel;
        }
        if (type == BlockType::IMAGE) {
            j["imageUrl"] = imageUrl;
            j["caption"] = caption;
            j["alt"] = alt;
        }
        if (type == BlockType::LIST) {
            j["listItems"] = listItems;
        }
        return j;
    }
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

    nlohmann::json toJson() const {
        nlohmann::json j;
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
        j["wordCount"] = wordCount;
        j["readingTimeMinutes"] = readingTimeMinutes;
        j["confidenceScore"] = confidenceScore;
        j["plainText"] = plainText;

        nlohmann::json bList = nlohmann::json::array();
        for (const auto& b : blocks) {
            bList.push_back(b.toJson());
        }
        j["blocks"] = bList;
        return j;
    }
};

} // namespace newsbrain

#endif // NEWS_ARTICLE_H
