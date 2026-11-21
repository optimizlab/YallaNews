#ifndef YALLA_BRAIN_H
#define YALLA_BRAIN_H

#include "yalla_types.h"
#include "yalla_errors.h"

#ifdef __cplusplus
extern "C" {
#endif

#define YALLA_CORE_EXPORT __declspec(dllexport)
#define YALLA_CORE_ABI_VERSION 1

// Create a NewsBrain engine instance. configuration_json is optional (may be NULL).
// Returns NULL on failure. Every created brain must be destroyed with yalla_brain_destroy.
YALLA_CORE_EXPORT YallaBrain* yalla_brain_create(const char* configuration_json);

// Destroy a brain and release all associated resources. Safe to call with NULL.
YALLA_CORE_EXPORT void yalla_brain_destroy(YallaBrain* brain);

// Write a new editorial article from one or more sources.
// result_json receives a heap-allocated UTF-8 JSON string owned by the caller;
// release it with yalla_brain_free. On error result_json is set to NULL.
YALLA_CORE_EXPORT YallaStatus yalla_brain_write_article(
    YallaBrain* brain,
    const YallaEditorialRequest* request,
    char** result_json);

// Request cancellation of the currently running job on this brain. Thread-safe.
YALLA_CORE_EXPORT void yalla_brain_cancel(YallaBrain* brain);

// Release memory previously allocated by this library (e.g. result_json strings).
YALLA_CORE_EXPORT void yalla_brain_free(void* memory);

// Return the library version string (static lifetime, do not free).
YALLA_CORE_EXPORT const char* yalla_brain_version(void);

// Return the compile-time ABI version.
YALLA_CORE_EXPORT int32_t yalla_brain_abi_version(void);

#ifdef __cplusplus
}
#endif

#endif // YALLA_BRAIN_H
