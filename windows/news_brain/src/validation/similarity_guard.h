#ifndef YALLA_SIMILARITY_GUARD_H
#define YALLA_SIMILARITY_GUARD_H

#include "core/job_context.h"

#include <string>
#include <vector>

namespace yalla {

struct SimilarityReport {
    double max_phrase_overlap = 0.0;
    double headline_similarity = 0.0;
    double paragraph_structure_similarity = 0.0;
    bool distinctive_phrase_reuse = false;
    double score = 0.0;  // warning signal, not proof of plagiarism or originality
    std::vector<std::string> warnings;
};

// SimilarityGuard compares the generated article with source material using
// lightweight methods: normalized exact-phrase detection, token n-gram overlap,
// sentence-level similarity, headline and paragraph-structure comparison.
// Arabic matching accounts for normalization without collapsing unrelated
// expressions. Configurable thresholds.
class SimilarityGuard {
public:
    explicit SimilarityGuard(JobContext& job);

    SimilarityReport compare(const std::string& article,
                             const std::string& source,
                             const std::string& headline) const;

    static double jaccard(const std::vector<std::string>& a,
                          const std::vector<std::string>& b);

private:
    JobContext& job_;
    double phrase_overlap_threshold_ = 0.30;
};

} // namespace yalla

#endif // YALLA_SIMILARITY_GUARD_H
