#include "yalla_core.h"
#include <cstring>

static YallaLogCallback g_log_callback = nullptr;
static void* g_log_user_data = nullptr;

void yalla_internal_log(const char* level, const char* message) {
    if (g_log_callback) {
        g_log_callback(level, message, g_log_user_data);
    }
}

extern "C" {

YALLA_CORE_EXPORT void yalla_free_string(const char* str) {
    if (str) free(const_cast<char*>(str));
}

YALLA_CORE_EXPORT void yalla_free_article(YallaArticle* article) {
    // Article struct contains only pointers to strings managed elsewhere
    // This is a no-op for the C API
    (void)article;
}

YALLA_CORE_EXPORT const char* yalla_get_version() {
    return strdup("1.0.0-core");
}

YALLA_CORE_EXPORT void yalla_set_log_callback(YallaLogCallback callback, void* user_data) {
    g_log_callback = callback;
    g_log_user_data = user_data;
}

} // extern "C"