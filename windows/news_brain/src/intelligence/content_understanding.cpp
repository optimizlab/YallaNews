#include "content_understanding.h"
#include "language/language_detector.h"
#include "language/tokenizer.h"

#include <algorithm>

namespace yalla {

ContentUnderstandingEngine::ContentUnderstandingEngine(JobContext& job) : job_(job) {}

namespace {
std::string trim(const std::string& s) {
    size_t a = s.find_first_not_of(" \t\r\n");
    size_t b = s.find_last_not_of(" \t\r\n");
    if (a == std::string::npos) return "";
    return s.substr(a, b - a + 1);
}
} // namespace

UnderstandingResult ContentUnderstandingEngine::understand(const NormalizedSource& source) const {
    UnderstandingResult r;
    r.dominant_language = source.detected_language;

    const std::string& body = source.normalized_content;
    const std::string& title = source.title.empty() ? "" : source.title;

    // Sentence-level segmentation as the basic unit of understanding.
    auto sentences = Tokenizer::tokenize_sentences(body, 256);

    static const char* event_kws[] = {
        "announced", "declared", "launched", "signed", "agreed", "decided",
        "a déclaré", "a annoncé", "a lancé", "a signé", "a décidé",
        "أعلن", "أعلنت", "أطلق", "وقع", "اتفق", "قرر"
    };
    static const char* claim_kws[] = {
        "claimed", "alleged", "accused", "according to", "said", "reported",
        "prétend", "allègue", "selon", "a dit", "a rapporté",
        "زعم", "اتهم", "ادعى", "أشار", "قال"
    };

    for (const auto& s : sentences) {
        std::string t = s;
        for (auto& c : t) c = (char)std::tolower((unsigned char)c);
        bool is_claim = false;
        for (const char* kw : claim_kws) {
            if (t.find(kw) != std::string::npos) { is_claim = true; break; }
        }
        if (is_claim) { r.claims.push_back(s); continue; }
        bool is_event = false;
        for (const char* kw : event_kws) {
            if (t.find(kw) != std::string::npos) { is_event = true; break; }
        }
        if (is_event) {
            if (r.main_event.empty()) r.main_event = s;
            else r.secondary_events.push_back(s);
            continue;
        }
        r.statements.push_back(s);
    }

    // Title contributes the main event when nothing was detected.
    if (r.main_event.empty() && !title.empty()) r.main_event = trim(title);

    if (r.claims.empty() && !r.statements.empty()) {
        // Qualify unsupported statements as claims/uncertainties rather than facts.
        r.uncertainties.push_back("No explicit confirmation found for all statements in the source.");
    }

    if (r.main_event.empty()) r.main_event = "No clear main event identified in the supplied content.";
    return r;
}

} // namespace yalla
