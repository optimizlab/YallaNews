#include "../include/page_scanner.h"
#include "../include/http_fetcher.h"
#include <algorithm>
#include <sstream>
#include <cmath>
#include <regex>
#include <iostream>

namespace newsbrain {

static std::string safeUtf8Substr(const std::string& str, size_t maxBytes) {
    if (str.length() <= maxBytes) return str;
    size_t i = 0;
    size_t lastValid = 0;
    while (i < str.length()) {
        unsigned char c = static_cast<unsigned char>(str[i]);
        size_t charLen = 1;
        if ((c & 0x80) == 0) charLen = 1;
        else if ((c & 0xE0) == 0xC0) charLen = 2;
        else if ((c & 0xF0) == 0xE0) charLen = 3;
        else if ((c & 0xF8) == 0xF0) charLen = 4;

        if (i + charLen > maxBytes) break;
        i += charLen;
        lastValid = i;
    }
    return str.substr(0, lastValid);
}

PageScanner::PageScanner() = default;
PageScanner::~PageScanner() = default;

NodeType PageScanner::mapTagToNodeType(const std::string& tag) const {
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

PageSkeleton PageScanner::scan(const std::string& url) {
    std::string html = HttpFetcher::instance().fetch(url);
    if (html.empty()) {
        std::cerr << "[PageScanner] Failed to fetch URL or returned empty content: " << url << std::endl;
    }
    return scanHtml(html, url);
}

PageSkeleton PageScanner::scanHtml(const std::string& html, const std::string& url) {
    PageSkeleton skeleton;
    skeleton.url = url;
    skeleton.canonicalUrl = url;

    HtmlParser parser;
    std::vector<RawHtmlNode> rawNodes = parser.parse(html);

    // Pass 1: Build structure
    pass1_BuildStructure(rawNodes, skeleton);

    // Pass 2: Extract metadata
    pass2_ExtractMetadata(rawNodes, skeleton);

    // Pass 3: Calculate visual & content signals
    pass3_CalculateSignals(skeleton);

    // Pass 4: Detect garbage & boilerplate
    pass4_FilterGarbage(skeleton);

    // Pass 5: Detect and rank Article Candidate regions
    pass5_DetectCandidates(skeleton);

    // Collect image candidates
    collectImages(skeleton, skeleton.images);

    return skeleton;
}

// Pass 1: Build semantic skeleton
void PageScanner::pass1_BuildStructure(const std::vector<RawHtmlNode>& rawNodes, PageSkeleton& skeleton) {
    if (rawNodes.empty()) return;

    skeleton.nodes.clear();
    skeleton.nodes.reserve(rawNodes.size());

    // Map from raw node index to PageNode index
    std::vector<NodeId> rawToPage(rawNodes.size(), -1);

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
            // Keep div if it has non-empty text, an id, class, or multiple children
            return !raw.text.empty() || raw.hasAttribute("class") || 
                   raw.hasAttribute("id") || raw.childrenIds.size() > 1;
        }
        // Retain nodes that have direct non-empty text
        return !raw.text.empty();
    };

    for (size_t i = 0; i < rawNodes.size(); ++i) {
        const auto& raw = rawNodes[i];
        if (!shouldKeepNode(raw)) continue;

        PageNode pn;
        pn.id = static_cast<NodeId>(skeleton.nodes.size());
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
        NodeId pageId = rawToPage[i];
        if (pageId < 0) continue;

        // Find nearest kept ancestor
        int rawParent = rawNodes[i].parentId;
        while (rawParent >= 0 && rawToPage[rawParent] < 0) {
            rawParent = rawNodes[rawParent].parentId;
        }

        if (rawParent >= 0 && rawToPage[rawParent] >= 0) {
            NodeId parentPageId = rawToPage[rawParent];
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
void PageScanner::pass2_ExtractMetadata(const std::vector<RawHtmlNode>& rawNodes, PageSkeleton& skeleton) {
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

            // OpenGraph
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
                    auto jLd = nlohmann::json::parse(raw.text);
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
                } catch (...) {
                    // Ignore JSON-LD parse errors gracefully
                }
            }
        }
    }

    if (meta.title.empty() && !meta.ogTitle.empty()) meta.title = meta.ogTitle;
    if (meta.description.empty() && !meta.ogDescription.empty()) meta.description = meta.ogDescription;
}

// Pass 3: Calculate signals
void PageScanner::pass3_CalculateSignals(PageSkeleton& skeleton) {
    if (skeleton.nodes.empty()) return;

    // Post-order traversal (bottom-up) to accumulate child metrics
    std::vector<int> postOrder;
    postOrder.reserve(skeleton.nodes.size());

    std::vector<bool> visited(skeleton.nodes.size(), false);
    std::vector<NodeId> stack;
    stack.push_back(0);

    while (!stack.empty()) {
        NodeId curr = stack.back();
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

    for (NodeId id : postOrder) {
        auto& node = skeleton.nodes[id];

        int subTextLen = static_cast<int>(node.text.length());
        int subLinkCount = (node.type == NodeType::LINK) ? 1 : 0;
        int subLinkTextLen = (node.type == NodeType::LINK) ? static_cast<int>(node.text.length()) : 0;
        int subImgCount = (node.type == NodeType::IMAGE) ? 1 : 0;

        for (NodeId childId : node.children) {
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

// Pass 4: Garbage and boilerplate filtering
void PageScanner::pass4_FilterGarbage(PageSkeleton& skeleton) {
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

        // Tag checks
        if (node.type == NodeType::NAV) {
            node.isGarbage = true;
            node.role = "navigation";
            continue;
        }
        if (node.type == NodeType::FOOTER) {
            node.isGarbage = true;
            node.role = "footer";
            continue;
        }
        if (node.type == NodeType::ASIDE) {
            node.isGarbage = true;
            node.role = "sidebar";
            continue;
        }

        // High link density with short/medium text is almost certainly navigation
        if (node.linkDensity > 0.65f && node.textLength < 400 && node.children.size() > 2) {
            node.isGarbage = true;
            node.role = "navigation";
            continue;
        }

        // Keyword checks
        if (matchesAny(combinedClassId, kAdKeywords)) {
            node.isGarbage = true;
            node.role = "advertisement";
        } else if (matchesAny(combinedClassId, kNavKeywords)) {
            node.isGarbage = true;
            node.role = "navigation";
        } else if (matchesAny(combinedClassId, kFooterKeywords)) {
            node.isGarbage = true;
            node.role = "footer";
        } else if (matchesAny(combinedClassId, kSocialKeywords)) {
            node.isGarbage = true;
            node.role = "social";
        } else if (matchesAny(combinedClassId, kCommentKeywords)) {
            node.isGarbage = true;
            node.role = "comments";
        } else if (matchesAny(combinedClassId, kSidebarKeywords)) {
            node.isGarbage = true;
            node.role = "sidebar";
        }
    }
}

// Pass 5: Detect and rank Article Candidate regions
void PageScanner::pass5_DetectCandidates(PageSkeleton& skeleton) {
    skeleton.candidates.clear();

    auto countParagraphsAndMembers = [&](NodeId rootId, int& outPCount, std::vector<NodeId>& outMembers) {
        outPCount = 0;
        outMembers.clear();

        std::vector<NodeId> q;
        q.push_back(rootId);
        size_t idx = 0;

        while (idx < q.size()) {
            NodeId currId = q[idx++];
            const auto& node = skeleton.nodes[currId];
            if (node.isGarbage) continue;

            outMembers.push_back(currId);
            if (node.type == NodeType::PARAGRAPH && node.text.length() >= 20) {
                outPCount++;
            }

            for (NodeId ch : node.children) {
                q.push_back(ch);
            }
        }
    };

    static const std::vector<std::string> kPositiveTokens = {
        "article", "story", "post", "body", "content", "entry", "main-content", "news-body", "article-text"
    };

    for (const auto& node : skeleton.nodes) {
        if (node.isGarbage) continue;

        // Consider container candidates: ARTICLE, MAIN, SECTION, DIV
        if (node.type != NodeType::ARTICLE && node.type != NodeType::MAIN && 
            node.type != NodeType::SECTION && node.type != NodeType::DIV) {
            continue;
        }

        // Must have at least 150 characters of text
        if (node.textLength < 150) continue;

        int pCount = 0;
        std::vector<NodeId> members;
        countParagraphsAndMembers(node.id, pCount, members);

        if (pCount < 1 && node.textLength < 300) continue;

        // Base score: 1 point per 50 characters of non-link text
        int nonLinkTextLen = std::max(0, node.textLength - node.linkTextLength);
        float score = static_cast<float>(nonLinkTextLen) / 50.0f;

        // Paragraph bonus
        score += static_cast<float>(pCount) * 8.0f;

        // Semantic tag bonus
        if (node.type == NodeType::ARTICLE) score += 40.0f;
        if (node.type == NodeType::MAIN) score += 30.0f;

        // Semantic class name bonus
        std::string classId = HtmlParser::toLower(node.className + " " + node.idAttr);
        for (const auto& tok : kPositiveTokens) {
            if (classId.find(tok) != std::string::npos) {
                score += 25.0f;
                break;
            }
        }

        // Link density penalty
        if (node.linkDensity > 0.3f) {
            score *= (1.0f - node.linkDensity);
        }

        // Depth balance (neither too shallow nor extremely deep)
        if (node.depth >= 2 && node.depth <= 7) {
            score += 10.0f;
        }

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

            // Preview text from first 200 chars
            for (NodeId memId : members) {
                const auto& memNode = skeleton.nodes[memId];
                if (memNode.type == NodeType::PARAGRAPH && !memNode.text.empty()) {
                    cand.previewText = safeUtf8Substr(memNode.text, 200);
                    break;
                }
            }
            if (cand.previewText.empty() && !node.text.empty()) {
                cand.previewText = safeUtf8Substr(node.text, 200);
            }

            skeleton.candidates.push_back(cand);
        }
    }

    // Sort candidates descending by score
    std::sort(skeleton.candidates.begin(), skeleton.candidates.end(), [](const ArticleCandidate& a, const ArticleCandidate& b) {
        return a.score > b.score;
    });

    // Mark role of top candidate in PageNodes
    if (!skeleton.candidates.empty()) {
        NodeId topRoot = skeleton.candidates[0].rootNodeId;
        skeleton.nodes[topRoot].role = "article-candidate";
    }
}

// Collect image candidates
void PageScanner::collectImages(const PageSkeleton& skeleton, std::vector<ImageCandidate>& outImages) {
    outImages.clear();

    for (const auto& node : skeleton.nodes) {
        if (node.type == NodeType::IMAGE) {
            std::string src = node.attributes.count("src") ? node.attributes.at("src") : "";
            if (src.empty() && node.attributes.count("data-src")) src = node.attributes.at("data-src");
            if (src.empty() && node.attributes.count("data-original")) src = node.attributes.at("data-original");

            if (src.empty() || src.rfind("data:", 0) == 0) continue; // ignore inline base64/tracking

            ImageCandidate ic;
            ic.src = src;
            ic.alt = node.attributes.count("alt") ? node.attributes.at("alt") : "";
            ic.nodeId = node.id;

            // Check if inside <figure> with <figcaption>
            if (node.parent >= 0 && skeleton.nodes[node.parent].type == NodeType::FIGURE) {
                for (NodeId sibId : skeleton.nodes[node.parent].children) {
                    if (skeleton.nodes[sibId].type == NodeType::FIGCAPTION) {
                        ic.caption = skeleton.nodes[sibId].text;
                        break;
                    }
                }
            }
            if (ic.caption.empty() && node.attributes.count("title")) {
                ic.caption = node.attributes.at("title");
            }

            // Dimension estimation
            if (node.attributes.count("width")) {
                try { ic.width = std::stoi(node.attributes.at("width")); } catch (...) {}
            }
            if (node.attributes.count("height")) {
                try { ic.height = std::stoi(node.attributes.at("height")); } catch (...) {}
            }

            // Exclude icons / avatars / trackers (< 100x100 if dimensions given)
            if (ic.width > 0 && ic.width < 100 && ic.height > 0 && ic.height < 100) continue;

            outImages.push_back(ic);
        }
    }

    // Mark lead image
    if (!outImages.empty()) {
        // Prefer image matching og:image, else the first prominent image
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

} // namespace newsbrain
