#ifndef YALLA_CORE_BRAIN_H
#define YALLA_CORE_BRAIN_H

#include "job_context.h"
#include "yalla_errors.h"
#include "yalla_types.h"

#include <cstddef>
#include <cstdint>
#include <memory>
#include <string>

namespace yalla {

// Configuration for a NewsBrain instance.
struct BrainConfig {
    JobLimits limits;
    bool deterministic_only = true;  // when true, only the deterministic writer is used
};

// The Brain owns one job at a time (single concurrent job per instance,
// per spec section 9). It coordinates the layered pipeline.
class Brain {
public:
    explicit Brain(const BrainConfig& config);
    ~Brain();

    Brain(const Brain&) = delete;
    Brain& operator=(const Brain&) = delete;

    bool is_valid() const { return valid_; }

    Status write_article(const YallaEditorialRequest& request,
                         std::string& out_json);

    void cancel() { if (job_) job_->request_cancellation(); }

    const BrainConfig& config() const { return config_; }

private:
    BrainConfig config_;
    std::unique_ptr<JobContext> job_;
    bool valid_ = false;
};

} // namespace yalla

#endif // YALLA_CORE_BRAIN_H
