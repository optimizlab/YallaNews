#include "EntityEngine.h"
#include "language/language_detector.h"

#include <algorithm>
#include <cstdio>
#include <cstring>

namespace yalla {

EntityEngine::EntityEngine(JobContext& job) : job_(job) {}

std::vector<Entity> EntityEngine::extract_entities(const std::string& title,
                                                    const std::string& body,
                                                    const std::string& language) const {
    std::vector<Entity> entities;
    entities.reserve(std::min(size_t(job_.limits().max_entities), size_t(64)));

    auto add_entity = [&](const std::string& name, const std::string& type,
                          double confidence) {
        if (entities.size() >= (size_t)job_.limits().max_entities) return;
        // Skip duplicates by name within this job.
        for (const auto& e : entities) {
            if (e.name == name) return;
        }
        Entity ent;
        char buf[16];
        std::snprintf(buf, sizeof(buf), "E%03d", static_cast<int>(entities.size() + 1));
        ent.id = buf;
        ent.name = name;
        ent.canonical = name;  // canonical form preserved separately in a full implementation
        ent.type = type;
        ent.original_language = language;
        ent.confidence = confidence;
        entities.push_back(std::move(ent));
    };

    std::string text = title + " " + body;

    // Person title markers per language (non-exhaustive, deterministic).
    static const char* markers[] = {
        "president", "minister", "director", "mayor", "governor",
        "président", "ministre", "directeur", "maire",
        "الرئيس", "الوزير", "المدير", "العمدة", "المحافظ"
    };

    for (const char* m : markers) {
        size_t pos = 0;
        while ((pos = text.find(m, pos)) != std::string::npos) {
            size_t start = pos;
            while (start > 0 && !std::isspace((unsigned char)text[start - 1])) --start;
            size_t end = pos + std::strlen(m);
            while (end < text.size() && !std::isspace((unsigned char)text[end])) ++end;
            if (end > start) add_entity(text.substr(start, end - start), "person", 0.6);
            pos = end;
        }
    }

    // Country/city cues (deterministic, small set).
    static const struct { const char* name; const char* type; } places[] = {
        {"france", "country"}, {"france", "country"},
        {"egypt", "country"}, {"paris", "city"}, {"cairo", "city"},
        {"london", "city"}, {"washington", "city"}, {"paris", "city"}
    };
    for (const auto& p : places) {
        size_t pos = text.find(p.name);
        if (pos != std::string::npos) add_entity(p.name, p.type, 0.7);
    }

    return entities;
}

} // namespace yalla
