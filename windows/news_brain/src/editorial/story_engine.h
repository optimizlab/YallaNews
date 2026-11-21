#ifndef YALLA_STORY_ENGINE_H
#define YALLA_STORY_ENGINE_H

#include "core/job_context.h"
#include "intelligence/content_understanding.h"
#include "yalla_editorial.h"

#include <string>

namespace yalla {

// StoryEngine determines the story behind the information without inventing
// motivations, implications or consequences.
class StoryEngine {
public:
    explicit StoryEngine(JobContext& job);

    struct Story {
        std::string main_news;
        std::string newsworthy_basis;
        std::string important_development;
        std::string essential_info;
        std::string secondary_info;
        std::string necessary_context;
        std::string not_established;
        std::string should_not_include;
        double confidence = 0.0;
    };

    Story derive(const UnderstandingResult& understanding,
                 const EventRepresentation& event) const;

private:
    JobContext& job_;
};

} // namespace yalla

#endif // YALLA_STORY_ENGINE_H
