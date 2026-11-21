#ifndef YALLA_CORE_HPP
#define YALLA_CORE_HPP

#include "yalla_brain.h"
#include "yalla_errors.h"
#include "yalla_editorial.h"

#include <cstdint>
#include <memory>
#include <string>

// Thin C++ wrapper around the stable C ABI. Optional convenience layer.
namespace yalla {

class Brain {
public:
    explicit Brain(const char* configuration_json = nullptr);
    ~Brain();

    Brain(const Brain&) = delete;
    Brain& operator=(const Brain&) = delete;
    Brain(Brain&&) noexcept;
    Brain& operator=(Brain&&) noexcept;

    bool is_valid() const { return brain_ != nullptr; }

    // Writes an article and returns the result JSON as an owned std::string.
    // Returns non-OK status on failure.
    Status write_article(const YallaEditorialRequest& request, std::string& out_json);

    void cancel();

private:
    YallaBrain* brain_ = nullptr;
};

} // namespace yalla

#endif // YALLA_CORE_HPP
