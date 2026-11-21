#include "news_writer.h"
#include "language/arabic_normalizer.h"

#include <cstdio>

namespace yalla {

NewsWriter::NewsWriter(JobContext& job) : job_(job) {}

GenerationResult NewsWriter::write(const EditorialPlan& plan,
                                    const std::vector<Fact>& facts,
                                    const std::vector<Evidence>& evidence,
                                    const std::vector<Entity>& entities,
                                    const EventRepresentation& event,
                                    const GenerationOptions& options) const {
    (void)evidence;
    GenerationResult result;
    result.status = Status::OK;
    result.language = plan.target_language.empty() ? options.language : plan.target_language;
    result.language = result.language.empty() ? "en" : result.language;
    result.article_type = plan.article_type;

    // Stage C: headline derived from the main message, not copied from source.
    char hbuf[256];
    const char* prefix = (plan.article_type == "breaking_news") ? "Breaking" : "Report";
    const char* subject = plan.main_message.empty() ? "news development reported" : plan.main_message.c_str();
    std::snprintf(hbuf, sizeof(hbuf), "%s: %s", prefix, subject);
    result.headline = hbuf;

    // Stage D: introduction = central development plus key supported info.
    std::string intro;
    if (!plan.main_message.empty()) {
        intro = plan.main_message;
        if (!event.summary.empty() && event.summary != plan.main_message)
            intro += ". " + event.summary;
    } else {
        intro = "A news development has been reported based on the supplied source material.";
    }

    // Stage E: body organized into sections from supported facts (not source order).
    std::vector<std::pair<std::string, std::string>> body;
    std::string section_text = "The reported development involves ";
    bool any_confirmed = false;
    for (const auto& f : facts) {
        if (f.fact_type == "allegation" || f.fact_type == "unknown") continue;
        if (!section_text.empty() && section_text.back() != ' ') section_text += " ";
        section_text += f.subject + " " + f.predicate + " " + f.object + ".";
        if (f.fact_type == "confirmed") any_confirmed = true;
        if (body.size() >= 3) break;
    }
    if (!any_confirmed) {
        section_text = "No independently confirmable facts were established in the supplied content.";
    }
    body.emplace_back("The development", section_text);

    if (!entities.empty()) {
        std::string actors = "Key actors mentioned: ";
        for (size_t i = 0; i < entities.size() && i < 5; ++i) {
            if (i) actors += ", ";
            actors += entities[i].name;
        }
        actors += ".";
        body.emplace_back("Actors", actors);
    }

    // Stage F: conclusion = confirmed consequence / position / unresolved question.
    std::string conclusion;
    if (!plan.conclusion_objective.empty())
        conclusion = plan.conclusion_objective + ". ";
    if (any_confirmed) {
        conclusion += "A confirmed consequence or official position is not stated beyond what the source reports.";
    } else {
        conclusion += "No further confirmed consequence is available from the supplied information; unattributed claims are treated as allegations.";
    }
    result.introduction = intro;
    result.body = std::move(body);
    result.conclusion = conclusion;
    return result;
}

} // namespace yalla
