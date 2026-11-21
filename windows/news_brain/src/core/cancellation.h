#ifndef YALLA_CANCELLATION_H
#define YALLA_CANCELLATION_H

#include <atomic>

// Cooperative cancellation token shared between the engine and the host.
class CancellationToken {
public:
    CancellationToken() = default;

    void request_cancellation() { cancelled_.store(true, std::memory_order_relaxed); }
    bool is_cancelled() const { return cancelled_.load(std::memory_order_relaxed); }
    void reset() { cancelled_.store(false, std::memory_order_relaxed); }

private:
    std::atomic<bool> cancelled_{false};
};

#endif // YALLA_CANCELLATION_H
