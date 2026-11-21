#ifndef YALLA_EDITORIAL_PLANNER_H
#define YALLA_EDITORIAL_PLANNER_H

#include "core/job_context.h"
#include "editorial/story_engine.h"
#include "yalla_editorial.h"

#include <string>
#include <vector>

namespace yalla {

// EditorialPlanner makes editorial decisions before writing, producing a plan
// whose selected article type influences structure and style.
class EditorialPlanner {
public:
    explicit EditorialPlanner(JobContext& job);

    EditorialPlan plan(const StoryEngine::Story& story,
                       const std::vector<Fact>& facts,
                       const std::string& output_language,
                       const std::string& requested_type,
                       int32_t target_length) const;

private:
    JobContext& job_;
};

} // namespace yalla

#endif // YALLA_EDITORIAL_PLANNER_H
