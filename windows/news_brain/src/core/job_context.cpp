#include "job_context.h"

#include <cstring>

namespace yalla {

JobContext::JobContext(const JobLimits& limits)
    : arena_(limits.arena_bytes), limits_(limits) {}

JobContext::~JobContext() = default;

char* JobContext::dup_string(const char* src) {
    if (!src) return nullptr;
    size_t len = std::strlen(src);
    char* dst = static_cast<char*>(arena_.allocate(len + 1, 1));
    if (!dst) return nullptr;
    std::memcpy(dst, src, len + 1);
    return dst;
}

char* JobContext::dup_string(const std::string& src) {
    return dup_string(src.c_str());
}

int32_t JobContext::check_cancellation() const {
    return is_cancelled() ? static_cast<int32_t>(Status::CANCELLED) : static_cast<int32_t>(Status::OK);
}

} // namespace yalla
