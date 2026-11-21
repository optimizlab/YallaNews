#ifndef YALLA_EVENT_ENGINE_H
#define YALLA_EVENT_ENGINE_H

#include "core/job_context.h"
#include "intelligence/content_understanding.h"
#include "yalla_editorial.h"

#include <string>

namespace yalla {

// EventUnderstandingEngine classifies whether the input describes a new event,
// an update, a reaction, a historical event, an opinion, or several unrelated
// events. The representation is temporary and discarded after the job.
class EventEngine {
public:
    explicit EventEngine(JobContext& job);

    EventRepresentation classify(const std::string& title,
                                 const std::string& body,
                                 const UnderstandingResult& understanding) const;

private:
    JobContext& job_;
};

} // namespace yalla

#endif // YALLA_EVENT_ENGINE_H
