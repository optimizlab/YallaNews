#ifndef YALLA_JOB_CONTEXT_H
#define YALLA_JOB_CONTEXT_H

#include "arena.h"
#include "cancellation.h"
#include "yalla_errors.h"

#include <cstddef>
#include <cstdint>
#include <memory>
#include <string>
#include <vector>

namespace yalla {

// Recommended per-job limits (spec section 9). Configurable per instance.
struct JobLimits {
    size_t max_input_bytes = 512 * 1024;      // 512 KiB
    size_t max_title_bytes = 2 * 1024;        // 2 KiB
    int32_t max_sources = 5;
    int32_t max_paragraphs = 256;
    int32_t max_facts = 256;
    int32_t max_entities = 128;
    int32_t max_evidence = 512;
    size_t max_output_bytes = 32 * 1024;      // 32 KiB
    size_t arena_bytes = 16 * 1024 * 1024;    // 16 MiB working memory
};

// One job-scoped context. All temporary allocations for a job live in the
// arena and are released when the context is destroyed. No article memory
// persists between jobs.
class JobContext {
public:
    explicit JobContext(const JobLimits& limits);
    ~JobContext();

    JobContext(const JobContext&) = delete;
    JobContext& operator=(const JobContext&) = delete;

    ArenaAllocator& arena() { return arena_; }
    const ArenaAllocator& arena() const { return arena_; }
    CancellationToken& cancellation() { return cancel_; }
    const CancellationToken& cancellation() const { return cancel_; }

    const JobLimits& limits() const { return limits_; }

    // Duplicate a null-terminated string into the arena. Returns nullptr on OOM.
    char* dup_string(const char* src);
    char* dup_string(const std::string& src);

    void request_cancellation() { cancel_.request_cancellation(); }
    bool is_cancelled() const { return cancel_.is_cancelled(); }

    // Check cancellation; returns Status::CANCELLED when requested.
    int32_t check_cancellation() const;

private:
    ArenaAllocator arena_;
    CancellationToken cancel_;
    JobLimits limits_;
};

} // namespace yalla

#endif // YALLA_JOB_CONTEXT_H
