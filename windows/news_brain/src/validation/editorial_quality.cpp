#include "editorial_quality.h"

namespace yalla {

EditorialQualityEngine::EditorialQualityEngine(JobContext& job) : job_(job) {}

QualityReport EditorialQualityEngine::evaluate(const std::string& article,
                                                const std::string& headline,
                                                const std::string& language) const {
    QualityReport r;
    r.findings.clear();

    if (article.empty()) {
        r.clear = false; r.coherent = false; r.score = 0.0;
        r.findings.push_back("Article is empty.");
        return r;
    }
    if (headline.empty()) {
        r.headline_accurate = false;
        r.findings.push_back("Missing headline.");
    }
    // Basic structure check: introduction + at least one body sentence.
    size_t paragraphs = 1;
    for (char c : article) if (c == '\n') ++paragraphs;
    if (paragraphs < 2) {
        r.coherent = false;
        r.findings.push_back("Article lacks paragraph structure.");
    }
    // Attribution heuristic: check for unsupported absolute statements.
    const char* absolutes[] = {"always", "never", "tous", "كل", "أبداً"};
    for (const char* w : absolutes) {
        if (article.find(w) != std::string::npos) {
            r.unsupported_statements = true;
            r.findings.push_back(std::string("Absolute term present: ") + w);
            break;
        }
    }
    r.language_consistent = !language.empty();
    r.score = r.unsupported_statements ? 0.5 : (r.findings.empty() ? 1.0 : 0.75);
    return r;
}

} // namespace yalla
