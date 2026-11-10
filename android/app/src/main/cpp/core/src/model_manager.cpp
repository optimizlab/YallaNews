#include "yalla_core.h"
#include <string>
#include <vector>
#include <unordered_map>
#include <filesystem>
#include <fstream>
#include <mutex>
#include <thread>
#include <atomic>
#include <curl/curl.h>
#include <openssl/sha.h>
#include <iomanip>
#include <sstream>

struct YallaModelManager {
    std::string models_dir;
    std::unordered_map<std::string, YallaModelInfo> model_cache;
    std::mutex cache_mutex;
    std::atomic<bool> cancel_download{false};

    YallaModelManager(const std::string& dir) : models_dir(dir) {
        std::filesystem::create_directories(models_dir);
    }

    std::string model_path(const std::string& model_id) const {
        return models_dir + "/" + model_id + ".gguf";
    }

    std::string compute_sha256(const std::string& path) {
        std::ifstream file(path, std::ios::binary);
        if (!file) return "";

        SHA256_CTX ctx;
        SHA256_Init(&ctx);

        constexpr size_t BUFSIZE = 8192;
        char buffer[BUFSIZE];
        while (file.read(buffer, BUFSIZE) || file.gcount() > 0) {
            SHA256_Update(&ctx, buffer, file.gcount());
        }

        unsigned char hash[SHA256_DIGEST_LENGTH];
        SHA256_Final(hash, &ctx);

        std::ostringstream oss;
        for (int i = 0; i < SHA256_DIGEST_LENGTH; ++i) {
            oss << std::hex << std::setw(2) << std::setfill('0') << static_cast<int>(hash[i]);
        }
        return oss.str();
    }

    bool verify_checksum(const std::string& path, const std::string& expected) {
        std::string actual = compute_sha256(path);
        return !actual.empty() && actual == expected;
    }

    static size_t write_callback(void* contents, size_t size, size_t nmemb, void* userp) {
        std::ofstream* file = static_cast<std::ofstream*>(userp);
        size_t total = size * nmemb;
        file->write(static_cast<const char*>(contents), total);
        return total;
    }

    static int progress_callback(void* clientp, curl_off_t dltotal, curl_off_t dlnow,
                                 curl_off_t ultotal, curl_off_t ulnow) {
        auto* manager = static_cast<YallaModelManager*>(clientp);
        if (manager->cancel_download) return 1; // Cancel

        if (manager->progress_cb && dltotal > 0) {
            int progress = static_cast<int>((dlnow * 100) / dltotal);
            manager->progress_cb(progress, "Downloading...", manager->progress_user_data);
        }
        return 0;
    }

    YallaProgressCallback progress_cb = nullptr;
    void* progress_user_data = nullptr;
};

extern "C" {

YALLA_CORE_EXPORT YallaModelManagerHandle yalla_model_manager_create(const char* models_dir) {
    std::string dir = models_dir ? models_dir : "./models";
    return new YallaModelManager(dir);
}

YALLA_CORE_EXPORT void yalla_model_manager_destroy(YallaModelManagerHandle handle) {
    if (handle) delete static_cast<YallaModelManager*>(handle);
}

YALLA_CORE_EXPORT bool yalla_model_manager_download(YallaModelManagerHandle handle,
    const char* model_id, const char* url, const char* expected_checksum,
    YallaProgressCallback progress_cb, void* user_data) {
    if (!handle || !model_id || !url) return false;
    auto* manager = static_cast<YallaModelManager*>(handle);

    manager->cancel_download = false;
    manager->progress_cb = progress_cb;
    manager->progress_user_data = user_data;

    std::string path = manager->model_path(model_id);
    std::ofstream file(path, std::ios::binary);
    if (!file) return false;

    CURL* curl = curl_easy_init();
    if (!curl) return false;

    curl_easy_setopt(curl, CURLOPT_URL, url);
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, YallaModelManager::write_callback);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &file);
    curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(curl, CURLOPT_NOPROGRESS, 0L);
    curl_easy_setopt(curl, CURLOPT_XFERINFOFUNCTION, YallaModelManager::progress_callback);
    curl_easy_setopt(curl, CURLOPT_XFERINFODATA, manager);
    curl_easy_setopt(curl, CURLOPT_USERAGENT, "YallaNews/1.0");
    curl_easy_setopt(curl, CURLOPT_TIMEOUT, 300L); // 5 min timeout
    curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT, 30L);

    if (progress_cb) progress_cb(0, "Starting download...", user_data);

    CURLcode res = curl_easy_perform(curl);
    curl_easy_cleanup(curl);
    file.close();

    if (res != CURLE_OK) {
        std::filesystem::remove(path);
        if (progress_cb) progress_cb(0, "Download failed", user_data);
        return false;
    }

    if (progress_cb) progress_cb(100, "Verifying...", user_data);

    // Verify checksum if provided
    if (expected_checksum && *expected_checksum) {
        if (!manager->verify_checksum(path, expected_checksum)) {
            std::filesystem::remove(path);
            if (progress_cb) progress_cb(0, "Checksum verification failed", user_data);
            return false;
        }
    }

    if (progress_cb) progress_cb(100, "Download complete", user_data);
    return true;
}

YALLA_CORE_EXPORT bool yalla_model_manager_verify(YallaModelManagerHandle handle,
    const char* model_id, bool* verified) {
    if (!handle || !model_id || !verified) return false;
    auto* manager = static_cast<YallaModelManager*>(handle);

    std::filesystem::path path = manager->model_path(model_id);
    *verified = std::filesystem::exists(path);
    return true;
}

YALLA_CORE_EXPORT YallaModelInfo* yalla_model_manager_get_info(YallaModelManagerHandle handle,
    const char* model_id) {
    if (!handle || !model_id) return nullptr;
    auto* manager = static_cast<YallaModelManager*>(handle);

    std::lock_guard<std::mutex> lock(manager->cache_mutex);
    auto it = manager->model_cache.find(model_id);
    if (it != manager->model_cache.end()) {
        YallaModelInfo* info = new YallaModelInfo(it->second);
        return info;
    }

    std::filesystem::path path = manager->model_path(model_id);
    bool exists = std::filesystem::exists(path);
    uintmax_t size = exists ? std::filesystem::file_size(path) : 0;

    YallaModelInfo info{};
    info.model_id = strdup(model_id);
    info.version = strdup("1.0");
    info.quantization = strdup("Q4_K_M");
    info.size_bytes = static_cast<int64_t>(size);
    info.checksum = strdup("");
    info.hardware_profile = size > 2000000000 ? "high" : (size > 500000000 ? "medium" : "low");

    manager->model_cache[model_id] = info;
    return new YallaModelInfo(info);
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
    auto* manager = static_cast<YallaModelManager*>(handle);

    std::vector<std::string> models;
    for (const auto& entry : std::filesystem::directory_iterator(manager->models_dir)) {
        if (entry.path().extension() == ".gguf") {
            models.push_back(entry.path().stem().string());
        }
    }

    *count = static_cast<int32_t>(models.size());
    if (models.empty()) return nullptr;

    const char** result = new const char*[models.size()];
    for (size_t i = 0; i < models.size(); ++i) {
        result[i] = strdup(models[i].c_str());
    }
    return result;
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
    auto* manager = static_cast<YallaModelManager*>(handle);
    std::lock_guard<std::mutex> lock(manager->cache_mutex);
    manager->model_cache.erase(model_id);
}

YALLA_CORE_EXPORT int64_t yalla_model_manager_get_memory_usage(YallaModelManagerHandle handle) {
    // Estimate: model size + context + overhead
    return 0;
}

YALLA_CORE_EXPORT void yalla_model_manager_cancel_download(YallaModelManagerHandle handle) {
    if (handle) static_cast<YallaModelManager*>(handle)->cancel_download = true;
}

} // extern "C"