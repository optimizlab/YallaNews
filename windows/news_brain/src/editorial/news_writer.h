#ifndef YALLA_NEWS_WRITER_H
#define YALLA_NEWS_WRITER_H

#include "core/job_context.h"
#include "yalla_editorial.h"

#include <string>
#include <vector>

namespace yalla {

// NewsWriter composes a new article from an editorial plan and structured
// facts. It independently organizes information rather than paraphrasing the
// source sentence-by-sentence.
class NewsWriter {
public:
    explicit NewsWriter(JobContext& job);

    GenerationResult write(const EditorialPlan& plan,
                           const std::vector<Fact>& facts,
                           const std::vector<Evidence>& evidence,
                           const std::vector<Entity>& entities,
                           const EventRepresentation& event,
                           const GenerationOptions& options) const;

private:
    JobContext& job_;
};

} // namespace yalla

#endif // YALLA_NEWS_WRITER_H
