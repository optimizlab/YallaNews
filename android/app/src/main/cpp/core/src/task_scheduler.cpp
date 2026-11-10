#include "yalla_core.h"
#include <queue>
#include <thread>
#include <mutex>
#include <condition_variable>
#include <functional>
#include <atomic>
#include <unordered_map>
#include <chrono>

struct YallaTaskScheduler {
    int32_t max_concurrent;
    std::atomic<int32_t> active_count{0};
    std::queue<std::function<void()>> task_queue;
    std::mutex queue_mutex;
    std::condition_variable cv;
    std::vector<std::thread> workers;
    std::atomic<bool> running{true};
    std::unordered_map<uint64_t, std::function<void(bool, const char*)>> callbacks;
    std::atomic<uint64_t> next_task_id{1};

    YallaTaskScheduler(int32_t max_concurrent_) : max_concurrent(max_concurrent_) {
        for (int i = 0; i < max_concurrent; ++i) {
            workers.emplace_back([this] { worker_loop(); });
        }
    }

    ~YallaTaskScheduler() {
        running = false;
        cv.notify_all();
        for (auto& w : workers) {
            if (w.joinable()) w.join();
        }
    }

    void worker_loop() {
        while (running) {
            std::function<void()> task;
            {
                std::unique_lock<std::mutex> lock(queue_mutex);
                cv.wait(lock, [this] { return !task_queue.empty() || !running; });
                if (!running && task_queue.empty()) break;
                if (task_queue.empty()) continue;
                task = std::move(task_queue.front());
                task_queue.pop();
            }
            if (task) {
                active_count++;
                task();
                active_count--;
            }
        }
    }

    bool submit_task(std::function<void()> task) {
        std::lock_guard<std::mutex> lock(queue_mutex);
        if (active_count >= max_concurrent) return false;
        task_queue.push(std::move(task));
        cv.notify_one();
        return true;
    }
};

extern "C" {

YALLA_CORE_EXPORT YallaTaskSchedulerHandle yalla_task_scheduler_create(int32_t max_concurrent_tasks) {
    if (max_concurrent_tasks <= 0) max_concurrent_tasks = 4;
    return new YallaTaskScheduler(max_concurrent_tasks);
}

YALLA_CORE_EXPORT void yalla_task_scheduler_destroy(YallaTaskSchedulerHandle handle) {
    if (handle) delete static_cast<YallaTaskScheduler*>(handle);
}

YALLA_CORE_EXPORT bool yalla_task_scheduler_submit(YallaTaskSchedulerHandle handle,
    const char* task_json, YallaCompletionCallback callback, void* user_data) {
    if (!handle || !task_json) return false;
    auto* scheduler = static_cast<YallaTaskScheduler*>(handle);

    auto task = [task_json, callback, user_data]() {
        // Simulate async processing
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
        if (callback) {
            const char* result = "{\"success\":true,\"message\":\"Task completed\"}";
            callback(true, result, user_data);
        }
    };

    return scheduler->submit_task(std::move(task));
}

YALLA_CORE_EXPORT void yalla_task_scheduler_cancel_all(YallaTaskSchedulerHandle handle) {
    if (!handle) return;
    auto* scheduler = static_cast<YallaTaskScheduler*>(handle);
    std::lock_guard<std::mutex> lock(scheduler->queue_mutex);
    while (!scheduler->task_queue.empty()) scheduler->task_queue.pop();
}

YALLA_CORE_EXPORT int32_t yalla_task_scheduler_pending_count(YallaTaskSchedulerHandle handle) {
    if (!handle) return 0;
    auto* scheduler = static_cast<YallaTaskScheduler*>(handle);
    std::lock_guard<std::mutex> lock(scheduler->queue_mutex);
    return static_cast<int32_t>(scheduler->task_queue.size());
}

} // extern "C"