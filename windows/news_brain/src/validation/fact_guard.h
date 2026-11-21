#ifndef YALLA_FACT_GUARD_H
#define YALLA_FACT_GUARD_H

#include "core/job_context.h"
#include "yalla_editorial.h"

#include <string>
#include <vector>

namespace yalla {

struct StatementCheck {
    std::string statement;
    bool supported = false;
    bool correctly_attributed = false;
    bool converts_claim_to_fact = false;
    bool introduces_unsupported_detail = false;
    bool implies_unestablished_causality = false;
    bool overstates_certainty = false;
    std::string reason;
};

// FactGuard checks every factual statement in the generated article against
// the evidence. Statements without adequate evidence are removed, rewritten
// with qualification, or flagged.
class FactGuard {
public:
    explicit FactGuard(JobContext& job);

    std::vector<StatementCheck> check_article(const std::string& article,
                                              const std::vector<Fact>& facts,
                                              const std::vector<Evidence>& evidence) const;

    bool all_supported(const std::vector<StatementCheck>& checks) const;

private:
    JobContext& job_;
};

} // namespace yalla

#endif // YALLA_FACT_GUARD_H
