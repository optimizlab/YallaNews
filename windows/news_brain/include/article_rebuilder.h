#ifndef ARTICLE_REBUILDER_H
#define ARTICLE_REBUILDER_H

#include <string>
#include <vector>
#include "page_skeleton.h"
#include "article_brain.h"
#include "news_article.h"

namespace newsbrain {

class ArticleRebuilder {
public:
    ArticleRebuilder();
    ~ArticleRebuilder();

    // Reconstructs "human reading" NewsArticle from skeleton and classified nodes
    NewsArticle rebuild(
        const PageSkeleton& skeleton,
        const std::vector<ClassifiedNode>& classifiedNodes
    );

private:
    int calculateWordCount(const std::string& text) const;
    int estimateReadingTime(int wordCount) const;
};

} // namespace newsbrain

#endif // ARTICLE_REBUILDER_H
