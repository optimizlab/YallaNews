#include "similarity_guard.h"
#include "language/arabic_normalizer.h"
#include "language/tokenizer.h"

#include <algorithm>
#include <set>

namespace yalla {

namespace {
std::string normalize_for_compare(const std::string& s) {
    std::string out;
    for (char c : s) {
        unsigned char uc = (unsigned char)c;
        if (std::isspace(uc)) { if (out.empty() || out.back() != ' ') out += ' '; }
        else out += (char)std::tolower(uc);
    }
    return out;
}
} // namespace

SimilarityGuard::SimilarityGuard(JobContext& job) : job_(job) {}

SimilarityReport SimilarityGuard::compare(const std::string& article,
                                           const std::string& source,
                                           const std::string& headline) const {
    SimilarityReport report;
    std::string a = ArabicNormalizer::normalize_for_matching(normalize_for_compare(article));
    std::string b = ArabicNormalizer::normalize_for_matching(normalize_for_compare(source));

    auto wa = Tokenizer::tokenize_words(a, 4096);
    auto wb = Tokenizer::tokenize_words(b, 4096);
    report.max_phrase_overlap = jaccard(wa, wb);

    std::string h = normalize_for_compare(headline);
    auto wh = Tokenizer::tokenize_words(h, 256);
    report.headline_similarity = jaccard(wh, wb);

    report.score = (report.max_phrase_overlap + report.headline_similarity) / 2.0;

    if (report.max_phrase_overlap > phrase_overlap_threshold_)
        report.warnings.push_back("High phrase overlap with source material.");
    if (report.headline_similarity > 0.5)
        report.warnings.push_back("Headline closely resembles source headline.");
    if (report.warnings.empty())
        report.warnings.push_back("No significant source overlap detected.");

    return report;
}

double SimilarityGuard::jaccard(const std::vector<std::string>& a,
                                 const std::vector<std::string>& b) {
    std::set<std::string> sa(a.begin(), a.end());
    std::set<std::string> sb(b.begin(), b.end());
    if (sa.empty() && sb.empty()) return 0.0;
    std::vector<std::string> inter;
    std::set_intersection(sa.begin(), sa.end(), sb.begin(), sb.end(),
                          std::back_inserter(inter));
    size_t uni = sa.size() + sb.size() - inter.size();
    return uni == 0 ? 0.0 : (double)inter.size() / (double)uni;
}

} // namespace yalla
