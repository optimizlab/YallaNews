#ifndef ARTICLE_BRAIN_H
#define ARTICLE_BRAIN_H

#include <string>
#include <vector>
#include <memory>
#include "page_skeleton.h"
#include "news_article.h"

namespace newsbrain {

enum class NodeClassification {
    UNKNOWN = 0,
    TITLE,
    SUBTITLE,
    AUTHOR,
    DATE,
    LEAD_IMAGE,
    INLINE_IMAGE,
    BODY_PARAGRAPH,
    SECTION_HEADING,
    PULL_QUOTE,
    LIST_BLOCK,
    DISCARD_AD,
    DISCARD_RELATED,
    DISCARD_BOILERPLATE
};

struct ClassifiedNode {
    NodeId nodeId = -1;
    NodeClassification classification = NodeClassification::UNKNOWN;
    float confidence = 0.0f;
    std::string text;
    std::string caption;
    std::string imageUrl;
    int headingLevel = 2;
    std::vector<std::string> listItems;
};

class ArticleBrain {
public:
    ArticleBrain();
    ~ArticleBrain();

    // Analyzes top candidate region and classifies 20-100 constituent nodes
    std::vector<ClassifiedNode> classifyCandidateNodes(
        const PageSkeleton& skeleton,
        const ArticleCandidate& candidate
    );

private:
    // Feature extraction & classification for individual nodes
    ClassifiedNode evaluateNode(
        const PageNode& node,
        int nodeIndexInCandidate,
        int totalCandidateNodes,
        const PageSkeleton& skeleton,
        const ArticleCandidate& candidate
    );

    // Contextual refinement pass (e.g. ensure only one Title, pick Subtitle if adjacent, lead image detection)
    void refineClassifications(
        std::vector<ClassifiedNode>& classified,
        const PageSkeleton& skeleton
    );
};

} // namespace newsbrain

#endif // ARTICLE_BRAIN_H
