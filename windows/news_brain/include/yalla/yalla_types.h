#ifndef YALLA_TYPES_H
#define YALLA_TYPES_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct YallaBrain YallaBrain;
typedef struct YallaJob YallaJob;

typedef enum {
    YALLA_STATUS_OK = 0,
    YALLA_STATUS_INVALID_ARGUMENT = 1,
    YALLA_STATUS_OUT_OF_MEMORY = 2,
    YALLA_STATUS_INPUT_TOO_LARGE = 3,
    YALLA_STATUS_CANCELLED = 4,
    YALLA_STATUS_UNSUPPORTED_LANGUAGE = 5,
    YALLA_STATUS_GENERATION_FAILED = 6,
    YALLA_STATUS_VALIDATION_FAILED = 7,
    YALLA_STATUS_INTERNAL_ERROR = 8,
    YALLA_STATUS_NOT_INITIALIZED = 9,
} YallaStatus;

typedef enum {
    YALLA_EDITION_READY = 0,
    YALLA_EDITION_READY_WITH_WARNINGS = 1,
    YALLA_EDITION_NEEDS_REVIEW = 2,
    YALLA_EDITION_REJECTED = 3,
} YallaEditorialDecision;

typedef struct {
    const char* text;
    const char* language;
    const char* title;
    const char* source_url;
    const char* publisher;
    int64_t published_at;
} YallaSourceInput;

typedef struct {
    const YallaSourceInput* sources;
    int32_t source_count;
    const char* output_language;
    const char* article_type;
    const char* editorial_style;
    int32_t target_length;
    uint32_t flags;
} YallaEditorialRequest;

#ifdef __cplusplus
}
#endif

#endif // YALLA_TYPES_H
