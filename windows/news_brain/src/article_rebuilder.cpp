#include "../include/article_rebuilder.h"
#include <sstream>
#include <algorithm>
#include <cctype>

namespace newsbrain {

ArticleRebuilder::ArticleRebuilder() = default;
ArticleRebuilder::~ArticleRebuilder() = default;

int ArticleRebuilder::calculateWordCount(const std::string& text) const {
    if (text.empty()) return 0;
    int count = 0;
    bool inWord = false;

    for (unsigned char c : text) {
        if (std::isspace(c)) {
            inWord = false;
        } else {
            if (!inWord) {
                count++;
                inWord = true;
            }
        }
    }
    return count;
}

int ArticleRebuilder::estimateReadingTime(int wordCount) const {
    // Average reading speed: ~180-200 words per minute
    int minutes = wordCount / 180;
    return (minutes < 1) ? 1 : minutes;
}

NewsArticle ArticleRebuilder::rebuild(
    const PageSkeleton& skeleton,
    const std::vector<ClassifiedNode>& classifiedNodes
) {
    NewsArticle article;
    article.url = skeleton.url;
    article.canonicalUrl = skeleton.canonicalUrl;
    article.language = skeleton.metadata.language;
    article.siteName = skeleton.metadata.siteName;

    // Default metadata fallbacks
    article.title = skeleton.metadata.title;
    article.author = skeleton.metadata.author;
    article.publishDate = skeleton.metadata.publishDate;
    article.leadImageUrl = skeleton.metadata.ogImage;

    std::stringstream fullTextSs;

    for (const auto& cn : classifiedNodes) {
        switch (cn.classification) {
            case NodeClassification::TITLE:
                if (!cn.text.empty()) {
                    article.title = cn.text;
                }
                break;

            case NodeClassification::SUBTITLE:
                if (article.subtitle.empty() && !cn.text.empty()) {
                    article.subtitle = cn.text;
                    ArticleBlock blk;
                    blk.type = BlockType::SUBTITLE;
                    blk.text = cn.text;
                    article.blocks.push_back(blk);
                    fullTextSs << cn.text << "\n\n";
                }
                break;

            case NodeClassification::AUTHOR:
                if (!cn.text.empty()) {
                    article.author = cn.text;
                }
                break;

            case NodeClassification::DATE:
                if (!cn.text.empty()) {
                    article.publishDate = cn.text;
                }
                break;

            case NodeClassification::LEAD_IMAGE:
                if (!cn.imageUrl.empty()) {
                    article.leadImageUrl = cn.imageUrl;
                    article.leadImageCaption = cn.caption;
                }
                break;

            case NodeClassification::INLINE_IMAGE:
                if (!cn.imageUrl.empty()) {
                    ArticleBlock blk;
                    blk.type = BlockType::IMAGE;
                    blk.imageUrl = cn.imageUrl;
                    blk.caption = cn.caption;
                    article.blocks.push_back(blk);
                }
                break;

            case NodeClassification::BODY_PARAGRAPH:
                if (!cn.text.empty()) {
                    ArticleBlock blk;
                    blk.type = BlockType::PARAGRAPH;
                    blk.text = cn.text;
                    article.blocks.push_back(blk);
                    fullTextSs << cn.text << "\n\n";
                }
                break;

            case NodeClassification::SECTION_HEADING:
                if (!cn.text.empty()) {
                    ArticleBlock blk;
                    blk.type = BlockType::HEADING;
                    blk.headingLevel = cn.headingLevel;
                    blk.text = cn.text;
                    article.blocks.push_back(blk);
                    fullTextSs << cn.text << "\n\n";
                }
                break;

            case NodeClassification::PULL_QUOTE:
                if (!cn.text.empty()) {
                    ArticleBlock blk;
                    blk.type = BlockType::QUOTE;
                    blk.text = cn.text;
                    article.blocks.push_back(blk);
                    fullTextSs << "\"" << cn.text << "\"\n\n";
                }
                break;

            case NodeClassification::LIST_BLOCK:
                if (!cn.listItems.empty()) {
                    ArticleBlock blk;
                    blk.type = BlockType::LIST;
                    blk.listItems = cn.listItems;
                    article.blocks.push_back(blk);
                    for (const auto& item : cn.listItems) {
                        fullTextSs << "• " << item << "\n";
                    }
                    fullTextSs << "\n";
                }
                break;

            default:
                break;
        }
    }

    // If subtitle still empty, fallback to metadata description
    if (article.subtitle.empty() && !skeleton.metadata.description.empty()) {
        article.subtitle = skeleton.metadata.description;
    }

    // Lead image fallback to first skeleton image candidate
    if (article.leadImageUrl.empty() && !skeleton.images.empty()) {
        article.leadImageUrl = skeleton.images[0].src;
        article.leadImageCaption = skeleton.images[0].caption;
    }

    article.plainText = fullTextSs.str();
    article.wordCount = calculateWordCount(article.plainText);
    article.readingTimeMinutes = estimateReadingTime(article.wordCount);

    // Confidence scoring
    float score = 0.5f;
    if (!article.title.empty()) score += 0.2f;
    if (article.blocks.size() >= 3) score += 0.2f;
    if (!article.leadImageUrl.empty()) score += 0.1f;
    article.confidenceScore = std::min(1.0f, score);

    return article;
}

} // namespace newsbrain
