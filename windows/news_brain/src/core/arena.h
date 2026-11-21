#ifndef YALLA_ARENA_H
#define YALLA_ARENA_H

#include <cstddef>
#include <cstdint>
#include <memory>

// Bounded bump (arena) allocator for job-scoped memory. All allocations are
// released together on reset(); no individual free. Hard capacity ceiling
// enforces the 16 MiB working-memory budget.
class ArenaAllocator {
public:
    explicit ArenaAllocator(size_t capacity_bytes);
    ~ArenaAllocator();

    ArenaAllocator(const ArenaAllocator&) = delete;
    ArenaAllocator& operator=(const ArenaAllocator&) = delete;

    // Allocate size bytes aligned to `alignment`. Returns nullptr when the
    // remaining capacity would be exceeded (caller must treat as OOM).
    void* allocate(size_t size, size_t alignment = 8);

    // Release all allocations and reset the offset. Capacity is retained.
    void reset();

    size_t used() const { return offset_; }
    size_t capacity() const { return capacity_; }
    size_t remaining() const { return capacity_ > offset_ ? capacity_ - offset_ : 0; }
    bool exhausted() const { return offset_ >= capacity_; }

private:
    std::unique_ptr<uint8_t[]> buffer_;
    size_t capacity_ = 0;
    size_t offset_ = 0;
};

#endif // YALLA_ARENA_H
