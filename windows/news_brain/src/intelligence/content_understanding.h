#ifndef YALLA_CONTENT_UNDERSTANDING_H
#define YALLA_CONTENT_UNDERSTANDING_H

#include "core/job_context.h"
#include "input/input_adapter.h"
#include "yalla_editorial.h"

#include <string>
#include <vector>

namespace yalla {

// First intelligence module: determines what the news item communicates,
// producing structured representations (events, actors, statements, actions,
// causes, consequences, claims, opinions, uncertainties) rather than prose.
struct UnderstandingResult {
    std::string main_event;
    std::vector<std::string> secondary_events;
    std::vector<std::string> actors;
    std::vector<std::string> statements;
    std::vector<std::string> actions;
    std::vector<std::string> causes;
    std::vector<std::string> consequences;
    std::vector<std::string> claims;
    std::vector<std::string> opinions;
    std::vector<std::string> uncertainties;
    std::vector<std::string> missing_information;
    std::string dominant_language;
};

class ContentUnderstandingEngine {
public:
    explicit ContentUnderstandingEngine(JobContext& job);

    UnderstandingResult understand(const NormalizedSource& source) const;

private:
    JobContext& job_;
};

} // namespace yalla

#endif // YALLA_CONTENT_UNDERSTANDING_H
