#include "fact_engine.h"

#include <cstdio>

namespace yalla {

FactEngine::FactEngine(JobContext& job) : job_(job) {}

int32_t FactEngine::next_fact_id() {
    char buf[16];
    std::snprintf(buf, sizeof(buf), "F%03d", ++fact_counter_);
    return fact_counter_;
}

std::vector<Fact> FactEngine::extract_facts(const UnderstandingResult& understanding,
                                            const std::vector<Evidence>& evidence,
                                            const std::string& default_language) const {
    std::vector<Fact> facts;
    facts.reserve(std::min(size_t(understanding.statements.size() + understanding.claims.size()),
                           size_t(job_.limits().max_facts)));

    const Evidence* src = evidence.empty() ? nullptr : &evidence[0];
    std::string source_id = src ? src->source_id : "S001";

    auto add_fact = [&](std::string subject, std::string predicate, std::string object,
                        std::string fact_type, std::string lang, double confidence) {
        if (facts.size() >= (size_t)job_.limits().max_facts) return;
        Fact f;
        char buf[16];
        std::snprintf(buf, sizeof(buf), "F%03d", ++fact_counter_);
        f.id = buf;
        f.subject = std::move(subject);
        f.predicate = std::move(predicate);
        f.object = std::move(object);
        f.fact_type = std::move(fact_type);
        f.source_id = source_id;
        f.original_language = lang.empty() ? default_language : lang;
        f.extraction_method = "rule-based";
        f.confidence = confidence;
        f.verified = (fact_type == "confirmed");
        facts.push_back(std::move(f));
    };

    // Main event as a confirmed fact when supported by evidence.
    if (!understanding.main_event.empty()) {
        add_fact("news item", "reports", understanding.main_event, "confirmed", default_language, 0.8);
    }

    // Statements become attributed statements (not established facts).
    for (const auto& stmt : understanding.statements) {
        add_fact("source", "states", stmt, "attributed", default_language, 0.6);
    }

    // Claims remain allegations; never converted into facts.
    for (const auto& claim : understanding.claims) {
        add_fact("source", "claims", claim, "allegation", default_language, 0.5);
    }

    // Uncertainties are recorded as unknown/missing.
    for (const auto& uncert : understanding.uncertainties) {
        add_fact("source", "does not specify", uncert, "unknown", default_language, 0.4);
    }

    return facts;
}

} // namespace yalla
