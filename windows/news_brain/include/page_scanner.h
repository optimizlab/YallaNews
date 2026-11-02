#ifndef PAGE_SCANNER_H
#define PAGE_SCANNER_H

#include <string>
#include <vector>
#include <memory>
#include "page_skeleton.h"
#include "html_parser.h"

namespace newsbrain {

class PageScanner {
public:
    PageScanner();
    ~PageScanner();

    // Scan directly by URL (fetches via HttpFetcher)
    PageSkeleton scan(const std::string& url);

    // Scan raw HTML string
    PageSkeleton scanHtml(const std::string& html, const std::string& url = "");

private:
    // Pass 1: Build compact semantic PageNodes from raw HTML DOM
    void pass1_BuildStructure(const std::vector<RawHtmlNode>& rawNodes, PageSkeleton& skeleton);

    // Pass 2: Extract page metadata (Title, OG, JSON-LD, Author, Date, Canonical, etc.)
    void pass2_ExtractMetadata(const std::vector<RawHtmlNode>& rawNodes, PageSkeleton& skeleton);

    // Pass 3: Calculate visual & content signals (Text density, Link density, Paragraphs, Depth)
    void pass3_CalculateSignals(PageSkeleton& skeleton);

    // Pass 4: Detect and mark garbage/boilerplate (Nav, Ads, Footer, Cookies, Sidebars, Social)
    void pass4_FilterGarbage(PageSkeleton& skeleton);

    // Pass 5: Detect and rank Article Candidate regions
    void pass5_DetectCandidates(PageSkeleton& skeleton);

    // Internal helpers
    NodeType mapTagToNodeType(const std::string& tag) const;
    void collectImages(const PageSkeleton& skeleton, std::vector<ImageCandidate>& outImages);
    float computeNodeScore(const PageNode& node, const PageSkeleton& skeleton) const;
};

} // namespace newsbrain

#endif // PAGE_SCANNER_H
