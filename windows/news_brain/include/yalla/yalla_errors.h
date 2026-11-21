#ifndef YALLA_ERRORS_H
#define YALLA_ERRORS_H

#include <cstdint>

namespace yalla {

// Structured, job-local status codes mirrored in the public C ABI.
enum class Status : int32_t {
    OK = 0,
    INVALID_ARGUMENT = 1,
    OUT_OF_MEMORY = 2,
    INPUT_TOO_LARGE = 3,
    CANCELLED = 4,
    UNSUPPORTED_LANGUAGE = 5,
    GENERATION_FAILED = 6,
    VALIDATION_FAILED = 7,
    INTERNAL_ERROR = 8,
    NOT_INITIALIZED = 9,
};

inline const char* status_name(Status s) {
    switch (s) {
        case Status::OK: return "OK";
        case Status::INVALID_ARGUMENT: return "INVALID_ARGUMENT";
        case Status::OUT_OF_MEMORY: return "OUT_OF_MEMORY";
        case Status::INPUT_TOO_LARGE: return "INPUT_TOO_LARGE";
        case Status::CANCELLED: return "CANCELLED";
        case Status::UNSUPPORTED_LANGUAGE: return "UNSUPPORTED_LANGUAGE";
        case Status::GENERATION_FAILED: return "GENERATION_FAILED";
        case Status::VALIDATION_FAILED: return "VALIDATION_FAILED";
        case Status::INTERNAL_ERROR: return "INTERNAL_ERROR";
        case Status::NOT_INITIALIZED: return "NOT_INITIALIZED";
    }
    return "UNKNOWN";
}

} // namespace yalla

#endif // YALLA_ERRORS_H
