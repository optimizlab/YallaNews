#include "arena.h"

#include <cstdlib>

ArenaAllocator::ArenaAllocator(size_t capacity_bytes)
    : buffer_(capacity_bytes ? static_cast<uint8_t*>(std::malloc(capacity_bytes)) : nullptr),
      capacity_(capacity_bytes),
      offset_(0) {}

ArenaAllocator::~ArenaAllocator() = default;

void* ArenaAllocator::allocate(size_t size, size_t alignment) {
    if (size == 0) return nullptr;
    // Round offset up to alignment.
    size_t mask = alignment - 1;
    size_t aligned_offset = (offset_ + mask) & ~mask;
    if (aligned_offset > capacity_ || capacity_ - aligned_offset < size) {
        return nullptr; // would exceed hard budget
    }
    void* ptr = buffer_.get() + aligned_offset;
    offset_ = aligned_offset + size;
    return ptr;
}

void ArenaAllocator::reset() {
    offset_ = 0;
}
