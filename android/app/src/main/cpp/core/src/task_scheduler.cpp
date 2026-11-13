// Task Scheduler - Simple implementation
#include "yalla_core.h"
#include <string>
#include <vector>
#include <mutex>

struct YallaTaskScheduler {
    int maxConcurrent;
    std::vector<std::string> tasks;
    std::mutex mutex;

    YallaTaskScheduler(int maxConcurrent) : maxConcurrent(maxConcurrent) {}
};

extern "C" {

YALLA_CORE_EXPORT YallaTaskSchedulerHandle yalla_task_scheduler_create(int32_t maxConcurrentTasks) {
    return new YallaTaskScheduler(maxConcurrentTasks);
}

YALLA_CORE_EXPORT void yalla_task_scheduler_destroy(YallaTaskSchedulerHandle handle) {
    if (handle) delete static_cast<YallaTaskScheduler*>(handle);
}

YALLA_CORE_EXPORT bool yalla_task_scheduler_submit(YallaTaskSchedulerHandle handle,
    const char* taskJson, YallaCompletionCallback callback, void* userData) {
    if (!handle || !taskJson) return false;
    auto* scheduler = static_cast<YallaTaskScheduler*>(handle);
    scheduler->tasks.push_back(taskJson ? taskJson : "");
    return true;
}

YALLA_CORE_EXPORT void yalla_task_scheduler_cancelAll(YallaTaskSchedulerHandle handle) {
    if (!handle) return;
    auto* scheduler = static_cast<YallaTaskScheduler*>(handle);
    scheduler->tasks.clear();
}

YALLA_CORE_EXPORT int32_t yalla_task_schedulerPendingCount(YallaTaskSchedulerHandle handle) {
    if (!handle) return 0;
    auto* scheduler = static_cast<YallaTaskScheduler*>(handle);
    return static_cast<int32_t>(scheduler->tasks.size());
}

} // extern "C"
