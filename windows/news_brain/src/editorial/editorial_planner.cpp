#include "editorial_planner.h"
#include <cctype>

namespace yalla {

EditorialPlanner::EditorialPlanner(JobContext& job) : job_(job) {}

static std::string normalize_type(const std::string& t) {
    std::string r = t;
    for (auto& c : r) c = (char)std::tolower((unsigned char)c);
    if (r.find("break") != std::string::npos) return "breaking_news";
    if (r.find("government") != std::string::npos || r.find("announcement") != std::string::npos)
        return "government_announcement";
    if (r.find("sport") != std::string::npos) return "sports";
    if (r.find("econom") != std::string::npos || r.find("business") != std::string::npos)
        return "economy";
    if (r.find("politic") != std::string::npos) return "politics";
    if (r.find("tech") != std::string::npos) return "technology";
    if (r.find("health") != std::string::npos) return "health";
    if (r.find("culture") != std::string::npos) return "culture";
    return "general_news";
}

EditorialPlan EditorialPlanner::plan(const StoryEngine::Story& story,
                                      const std::vector<Fact>& facts,
                                      const std::string& output_language,
                                      const std::string& requested_type,
                                      int32_t target_length) const {
    (void)facts;
    EditorialPlan p;
    p.article_type = normalize_type(requested_type);
    if (p.article_type == "breaking_news") {
        p.angle = "Immediate development";
        p.headline_direction = "Short, factual lead with the central development.";
        p.introduction_objective = "Communicate what happened, who and when in the first sentences.";
        p.conclusion_objective = "State the confirmed consequence or official position, if any.";
    } else if (p.article_type == "government_announcement") {
        p.angle = "Official action and its stated effect.";
        p.headline_direction = "Name the issuing body and the announcement.";
        p.introduction_objective = "Summarize the announcement and who made it.";
        p.conclusion_objective = "Note when it takes effect, per the source.";
    } else {
        p.angle = story.newsworthy_basis;
        p.headline_direction = "Clear, informative headline summarizing the main development.";
        p.introduction_objective = "Communicate the central development and its most important supported information.";
        p.conclusion_objective = "Close with a confirmed consequence, official position or unresolved question when supported.";
    }
    p.main_message = story.main_news;
    p.target_audience = "general readership";
    p.target_language = output_language.empty() ? "en" : output_language;
    p.target_length = target_length > 0 ? target_length : 400;
    p.body_sections = {"The development", "Context and actors", "What remains unclear"};
    p.uncertainties = {story.not_established};
    p.confidence = story.confidence;
    return p;
}

} // namespace yalla
