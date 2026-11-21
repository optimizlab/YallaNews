#include "article_composer.h"

namespace yalla {

std::string ArticleComposer::join_body(const std::vector<std::pair<std::string, std::string>>& body) {
    std::string out;
    for (const auto& [heading, text] : body) {
        if (!heading.empty()) out += heading + "\n";
        out += text + "\n\n";
    }
    return out;
}

std::string ArticleComposer::compose(const GenerationResult& generated,
                                      const EditorialPlan& plan,
                                      size_t max_output_bytes) const {
    std::string article;
    article += "Headline: " + generated.headline + "\n";
    if (!generated.subtitle.empty()) article += "Subtitle: " + generated.subtitle + "\n";
    article += "\n" + generated.introduction + "\n\n";
    article += join_body(generated.body);
    if (!generated.conclusion.empty()) {
        article += "Conclusion: " + generated.conclusion + "\n";
    }
    if (article.size() > max_output_bytes) article.resize(max_output_bytes);
    return article;
}

} // namespace yalla
