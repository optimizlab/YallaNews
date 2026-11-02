#include "../include/article_brain.h"
#include "../include/html_parser.h"
#include <algorithm>
#include <regex>

namespace newsbrain {

ArticleBrain::ArticleBrain() = default;
ArticleBrain::~ArticleBrain() = default;

std::vector<ClassifiedNode> ArticleBrain::classifyCandidateNodes(
    const PageSkeleton& skeleton,
    const ArticleCandidate& candidate
) {
    std::vector<ClassifiedNode> result;
    result.reserve(candidate.memberNodeIds.size());

    int totalNodes = static_cast<int>(candidate.memberNodeIds.size());
    for (int i = 0; i < totalNodes; ++i) {
        NodeId memId = candidate.memberNodeIds[i];
        if (memId < 0 || memId >= static_cast<NodeId>(skeleton.nodes.size())) continue;

        const auto& node = skeleton.nodes[memId];
        ClassifiedNode cn = evaluateNode(node, i, totalNodes, skeleton, candidate);
        if (cn.classification != NodeClassification::UNKNOWN) {
            result.push_back(cn);
        }
    }

    // Contextual refinement pass
    refineClassifications(result, skeleton);

    return result;
}

ClassifiedNode ArticleBrain::evaluateNode(
    const PageNode& node,
    int nodeIndexInCandidate,
    int totalCandidateNodes,
    const PageSkeleton& skeleton,
    const ArticleCandidate& candidate
) {
    ClassifiedNode cn;
    cn.nodeId = node.id;
    cn.text = node.text;

    // Discard if marked garbage or empty
    if (node.isGarbage) {
        cn.classification = NodeClassification::DISCARD_BOILERPLATE;
        return cn;
    }

    std::string classId = HtmlParser::toLower(node.className + " " + node.idAttr + " " + node.role);

    // Advertisement / Sponsored / Related check
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

    // Check Title
    if (node.tag == "h1" || classId.find("article-title") != std::string::npos || 
        classId.find("headline") != std::string::npos) {
        cn.classification = NodeClassification::TITLE;
        cn.confidence = 0.95f;
        return cn;
    }

    // Check Author / Byline
    if (classId.find("author") != std::string::npos || 
        classId.find("byline") != std::string::npos || 
        classId.find("writer") != std::string::npos) {
        if (node.text.length() > 0 && node.text.length() < 100) {
            cn.classification = NodeClassification::AUTHOR;
            cn.confidence = 0.90f;
            return cn;
        }
    }
    // Arabic author markers: "كتب:", "بقلم:", "محرر"
    if (node.text.rfind("كتب:", 0) == 0 || node.text.rfind("بقلم:", 0) == 0 ||
        node.text.rfind("متابعة:", 0) == 0 || node.text.rfind("By ", 0) == 0) {
        if (node.text.length() < 80) {
            cn.classification = NodeClassification::AUTHOR;
            cn.confidence = 0.88f;
            return cn;
        }
    }

    // Check Date / Timestamp
    if (node.tag == "time" || classId.find("date") != std::string::npos || 
        classId.find("time") != std::string::npos || classId.find("publish") != std::string::npos) {
        if (node.text.length() > 0 && node.text.length() < 80) {
            cn.classification = NodeClassification::DATE;
            cn.confidence = 0.88f;
            return cn;
        }
    }

    // Check Headings (H2, H3, H4)
    if (node.type == NodeType::HEADING) {
        cn.classification = NodeClassification::SECTION_HEADING;
        cn.headingLevel = 2;
        if (node.tag == "h3") cn.headingLevel = 3;
        else if (node.tag == "h4") cn.headingLevel = 4;
        cn.confidence = 0.85f;
        return cn;
    }

    // Check Blockquote / Quotes
    if (node.type == NodeType::BLOCKQUOTE || classId.find("quote") != std::string::npos) {
        if (!node.text.empty()) {
            cn.classification = NodeClassification::PULL_QUOTE;
            cn.confidence = 0.85f;
            return cn;
        }
    }

    // Check Image
    if (node.type == NodeType::IMAGE) {
        std::string src = node.attributes.count("src") ? node.attributes.at("src") : "";
        if (src.empty() && node.attributes.count("data-src")) src = node.attributes.at("data-src");

        if (!src.empty() && src.rfind("data:", 0) != 0) {
            cn.imageUrl = src;
            cn.caption = node.attributes.count("alt") ? node.attributes.at("alt") : "";
            
            // Check if inside figure with figcaption
            if (node.parent >= 0 && skeleton.nodes[node.parent].type == NodeType::FIGURE) {
                for (NodeId ch : skeleton.nodes[node.parent].children) {
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

    // Check Paragraph
    if (node.type == NodeType::PARAGRAPH) {
        // High link density paragraph is usually an internal promo or related link
        if (node.linkDensity > 0.5f) {
            cn.classification = NodeClassification::DISCARD_RELATED;
            return cn;
        }

        // Subtitle / Lead paragraph check
        if (nodeIndexInCandidate <= 2 && (classId.find("sub") != std::string::npos || 
            classId.find("lead") != std::string::npos || classId.find("summary") != std::string::npos)) {
            cn.classification = NodeClassification::SUBTITLE;
            cn.confidence = 0.88f;
            return cn;
        }

        // Regular story paragraph (must have at least some non-trivial length)
        if (node.text.length() >= 15) {
            cn.classification = NodeClassification::BODY_PARAGRAPH;
            cn.confidence = 0.90f;
            return cn;
        }
    }

    // Check List
    if (node.type == NodeType::LIST) {
        std::vector<std::string> items;
        for (NodeId ch : node.children) {
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

void ArticleBrain::refineClassifications(
    std::vector<ClassifiedNode>& classified,
    const PageSkeleton& skeleton
) {
    bool hasTitle = false;
    bool hasLeadImage = false;

    for (auto& cn : classified) {
        if (cn.classification == NodeClassification::TITLE) {
            if (!hasTitle) {
                hasTitle = true;
            } else {
                // Secondary title converted to Section Heading
                cn.classification = NodeClassification::SECTION_HEADING;
                cn.headingLevel = 2;
            }
        } else if (cn.classification == NodeClassification::LEAD_IMAGE) {
            if (!hasLeadImage) {
                hasLeadImage = true;
            } else {
                cn.classification = NodeClassification::INLINE_IMAGE;
            }
        }
    }

    // If no lead image classified yet, and we have an image matching metadata og:image
    if (!hasLeadImage && !skeleton.images.empty()) {
        for (auto& cn : classified) {
            if (cn.classification == NodeClassification::INLINE_IMAGE) {
                cn.classification = NodeClassification::LEAD_IMAGE;
                break;
            }
        }
    }
}

} // namespace newsbrain
