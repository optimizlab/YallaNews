// Model Manager - Stub implementation
// Provides model download and management stubs
// llama.cpp integration is a future enhancement (Phase 2)

#include "yalla_core.h"
#include <string>
#include <vector>
#include <unordered_map>
#include <mutex>

struct YallaModelManager {
    std::string models_dir;
    std::unordered_map<std::string, bool> model_cache;  // Track which models are "loaded"
    std::mutex cache_mutex;

    YallaModelManager(const std::string& dir) : models_dir(dir) {}

    std::string model_path(const std::string& model_id) const {
        return models_dir + "/" + model_id + ".gguf";
    }
};

extern "C" {

YALLA_CORE_EXPORT YallaModelManagerHandle yalla_model_manager_create(const char* models_dir) {
    if (!models_dir) models_dir = "./models";
    return new YallaModelManager(models_dir);
}

YALLA_CORE_EXPORT void yalla_model_manager_destroy(YallaModelManagerHandle handle) {
    if (handle) delete static_cast<YallaModelManager*>(handle);
}

YALLA_CORE_EXPORT bool yalla_model_manager_download(YallaModelManagerHandle handle,
    const char* model_id, const char* url, const char* expected_checksum,
    YallaProgressCallback progress_cb, void* user_data) {
    // Stub implementation - model download is a future enhancement
    // Return false to indicate model not available yet
    (void)handle; (void)model_id; (void)url; (void)expected_checksum;
    (void)progress_cb; (void)user_data;
    return false;
}

YALLA_CORE_EXPORT bool yalla_model_manager_verify(YallaModelManagerHandle handle,
    const char* model_id, bool* verified) {
    if (!handle || !model_id || !verified) return false;
    *verified = false;  // No models downloaded yet
    return true;
}

YALLA_CORE_EXPORT YallaModelInfo* yalla_model_manager_get_info(YallaModelManagerHandle handle,
    const char* model_id) {
    if (!handle || !model_id) return nullptr;
    auto* info = new YallaModelInfo();
    info->model_id = model_id ? strdup(model_id) : strdup("");
    info->version = strdup("1.0");
    info->quantization = strdup("Q4_K_M");
    info->size_bytes = 0;
    info->checksum = strdup("");
    info->hardware_profile = strdup("low");
    return info;
}

YALLA_CORE_EXPORT void yalla_model_manager_free_info(YallaModelInfo* info) {
    if (!info) return;
    free(const_cast<char*>(info->model_id));
    free(const_cast<char*>(info->version));
    free(const_cast<char*>(info->quantization));
    free(const_cast<char*>(info->checksum));
    free(const_cast<char*>(info->hardware_profile));
    delete info;
}

YALLA_CORE_EXPORT const char** yalla_model_manager_list_models(YallaModelManagerHandle handle,
    int32_t* count) {
    if (!handle || !count) return nullptr;
    *count = 0;
    return nullptr;  // No models downloaded yet
}

YALLA_CORE_EXPORT void yalla_model_manager_free_list(const char** list, int32_t count) {
    if (!list) return;
    for (int i = 0; i < count; ++i) {
        free(const_cast<char*>(list[i]));
    }
    delete[] list;
}

YALLA_CORE_EXPORT void yalla_model_manager_unload(YallaModelManagerHandle handle, const char* model_id) {
    if (!handle || !model_id) return;
    // No-op: no models are loaded yet
}

YALLA_CORE_EXPORT int64_t yalla_model_manager_get_memory_usage(YallaModelManagerHandle handle) {
    if (!handle) return 0;
    return 0;  // No models loaded yet
}

} // extern "C"
