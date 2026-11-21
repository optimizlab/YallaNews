#ifndef YALLA_RESULT_SERIALIZER_H
#define YALLA_RESULT_SERIALIZER_H

#include "yalla_errors.h"
#include "yalla_editorial.h"

#include <string>
#include <vector>

namespace yalla {

// Minimal JSON builder producing the structured result per spec section 12.
// Escapes UTF-8 text safely; no external JSON dependency.
class JsonBuilder {
public:
    JsonBuilder() = default;

    static std::string escape(const std::string& s);

    std::string str() const { return buf_; }

    void begin_object();
    void end_object();
    void begin_array();
    void end_array();
    void key(const char* name);
    void value_string(const char* value);
    void value_string(const std::string& value);
    void value_string_null();
    void value_int(int64_t v);
    void value_double(double v);
    void value_bool(bool v);
    void comma();

private:
    std::string buf_;
    bool need_comma_ = false;
};

// Serialize the editorial result into the versioned JSON schema.
std::string serialize_result(const std::string& schema_version,
                             YallaEditorialDecision decision,
                             const GenerationResult& article,
                             const EditorialPlan& plan,
                             const std::vector<std::string>& warnings,
                             const std::vector<std::string>& source_ids,
                             int32_t fact_count,
                             int32_t supported_count,
                             int32_t unsupported_count,
                             const std::string& fact_check,
                             const std::string& similarity_check,
                             const std::string& quality_check);

} // namespace yalla

#endif // YALLA_RESULT_SERIALIZER_H
