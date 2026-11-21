#include "fact_guard.h"
#include "language/tokenizer.h"

namespace yalla {

FactGuard::FactGuard(JobContext& job) : job_(job) {}

std::vector<StatementCheck> FactGuard::check_article(const std::string& article,
                                                      const std::vector<Fact>& facts,
                                                      const std::vector<Evidence>& evidence) const {
    std::vector<StatementCheck> checks;
    auto sentences = Tokenizer::tokenize_sentences(article, 256);

    for (const auto& s : sentences) {
        StatementCheck c;
        c.statement = s;
        // Heuristic: a statement is supported when it shares a subject/predicate
        // pattern with an extracted fact; otherwise flag as unsupported.
        bool supported = false;
        for (const auto& f : facts) {
            if (s.find(f.subject) != std::string::npos && s.find(f.object) != std::string::npos) {
                supported = true;
                break;
            }
        }
        c.supported = supported;
        c.correctly_attributed = supported;
        if (!supported) {
            c.reason = "No supporting evidence found in extracted facts.";
            c.introduces_unsupported_detail = true;
            // A statement that mirrors an extracted allegation must stay an allegation,
            // never be promoted to an established fact.
            for (const auto& f : facts) {
                if (f.fact_type == "allegation" &&
                    (s.find(f.subject) != std::string::npos ||
                     s.find(f.object) != std::string::npos)) {
                    c.converts_claim_to_fact = true;
                    break;
                }
            }
        }
        checks.push_back(std::move(c));
    }
    return checks;
}

bool FactGuard::all_supported(const std::vector<StatementCheck>& checks) const {
    for (const auto& c : checks)
        if (!c.supported) return false;
    return true;
}

} // namespace yalla
