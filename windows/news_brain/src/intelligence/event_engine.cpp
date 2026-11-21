#include "event_engine.h"
#include <cctype>

#include <cstdio>

namespace yalla {

EventEngine::EventEngine(JobContext& job) : job_(job) {}

EventRepresentation EventEngine::classify(const std::string& title,
                                           const std::string& body,
                                           const UnderstandingResult& understanding) const {
    EventRepresentation rep;
    static const char* new_kws[] = {
        "announced", "declared", "launched", "today", "this morning",
        "a annoncé", "aujourd'hui", "ce matin", "أعلن", "اليوم"
    };
    static const char* update_kws[] = {
        "update", "follow-up", "develops", "continuing",
        "mise à jour", "suit", "يتبع", "تحديث"
    };
    static const char* reaction_kws[] = {
        "reacts", "responds", "welcomes", "criticizes",
        "réagit", "répond", "ي réag", "يرد"
    };

    std::string text = title + " " + body;
    for (auto& c : text) c = (char)std::tolower((unsigned char)c);

    std::string type = "historical";
    double confidence = 0.5;

    for (const char* kw : new_kws) {
        if (text.find(kw) != std::string::npos) { type = "new"; confidence = 0.8; break; }
    }
    if (type == "historical") {
        for (const char* kw : update_kws) {
            if (text.find(kw) != std::string::npos) { type = "update"; confidence = 0.75; break; }
        }
    }
    if (type == "historical") {
        for (const char* kw : reaction_kws) {
            if (text.find(kw) != std::string::npos) { type = "reaction"; confidence = 0.7; break; }
        }
    }

    rep.id = "EV001";
    rep.type = type;
    rep.summary = understanding.main_event.empty() ? title : understanding.main_event;
    rep.confidence = confidence;
    return rep;
}

} // namespace yalla
