#include "source_evidence.h"

#include <cstdio>

namespace yalla {

SourceEvidenceEngine::SourceEvidenceEngine(JobContext& job) : job_(job) {}

std::vector<Evidence> SourceEvidenceEngine::build_evidence(const NormalizedSource& source,
                                                            int32_t source_index) const {
    std::vector<Evidence> out;
    Evidence e;
    char buf[16];
    std::snprintf(buf, sizeof(buf), "S%03d", source_index + 1);
    e.source_id = buf;
    e.url = source.url.empty() ? "" : source.url;
    e.publisher = source.publisher.empty() ? "" : source.publisher;
    e.published_at = source.published_at;
    e.passage = source.normalized_content.empty() ? source.raw_content : source.normalized_content;
    if (e.passage.size() > 200) e.passage.resize(200);  // bounded evidence passage
    e.passage_offset = 0;
    e.passage_length = e.passage.size();
    e.source_language = source.detected_language.empty() ? "und" : source.detected_language;
    e.attribution = source.publisher.empty() ? "unspecified" : source.publisher;
    // Independence unknown unless established; never assume independent confirmation.
    e.independent = false;
    out.push_back(std::move(e));
    return out;
}

} // namespace yalla
