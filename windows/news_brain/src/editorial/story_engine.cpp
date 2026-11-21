#include "story_engine.h"

namespace yalla {

StoryEngine::StoryEngine(JobContext& job) : job_(job) {}

StoryEngine::Story StoryEngine::derive(const UnderstandingResult& understanding,
                                        const EventRepresentation& event) const {
    Story s;
    s.main_news = understanding.main_event;
    s.important_development = understanding.secondary_events.empty()
        ? "No secondary development reported."
        : understanding.secondary_events.front();
    s.essential_info = s.main_news;
    s.necessary_context = understanding.dominant_language.empty()
        ? "No additional context established."
        : "Reported in " + understanding.dominant_language + ".";
    s.not_established = "Completion date, exact figures and independent confirmation are not established unless stated in the source.";
    s.should_not_include = "Unverified quotations, invented causality, or unattributed opinions must not be included.";
    s.newsworthy_basis = event.type + " event: " + event.summary;
    s.confidence = event.confidence;
    return s;
}

} // namespace yalla
