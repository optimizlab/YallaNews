#ifndef YALLA_ARTICLE_COMPOSER_H
#define YALLA_ARTICLE_COMPOSER_H

#include "yalla_editorial.h"

#include <string>

namespace yalla {

// ArticleComposer assembles the final article text and metadata from a
// GenerationResult, enforcing length bounds and language consistency.
class ArticleComposer {
public:
    ArticleComposer() = default;

    std::string compose(const GenerationResult& generated,
                        const EditorialPlan& plan,
                        size_t max_output_bytes) const;

private:
    static std::string join_body(const std::vector<std::pair<std::string, std::string>>& body);
};

} // namespace yalla

#endif // YALLA_ARTICLE_COMPOSER_H
