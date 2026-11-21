#include "result_serializer.h"

#include <cstdio>

namespace yalla {

std::string JsonBuilder::escape(const std::string& s) {
    std::string out;
    out.reserve(s.size() + 8);
    for (char c : s) {
        switch (c) {
            case '"': out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\n': out += "\\n"; break;
            case '\r': out += "\\r"; break;
            case '\t': out += "\\t"; break;
            case '\b': out += "\\b"; break;
            case '\f': out += "\\f"; break;
            default:
                if ((unsigned char)c < 0x20) {
                    char tmp[8];
                    std::snprintf(tmp, sizeof(tmp), "\\u%04x", (unsigned char)c);
                    out += tmp;
                } else {
                    out += c;
                }
        }
    }
    return out;
}

void JsonBuilder::begin_object() {
    if (need_comma_) { buf_ += ','; need_comma_ = false; }
    buf_ += '{';
    need_comma_ = false;
}
void JsonBuilder::end_object() {
    buf_ += '}';
    need_comma_ = true;
}
void JsonBuilder::begin_array() {
    if (need_comma_) { buf_ += ','; need_comma_ = false; }
    buf_ += '[';
    need_comma_ = false;
}
void JsonBuilder::end_array() {
    buf_ += ']';
    need_comma_ = true;
}
void JsonBuilder::key(const char* name) {
    if (need_comma_) buf_ += ',';
    buf_ += '"';
    buf_ += escape(name);
    buf_ += "\":";
    need_comma_ = false;
}
void JsonBuilder::value_string(const char* v) {
    if (need_comma_) buf_ += ',';
    buf_ += '"';
    buf_ += escape(v ? v : "");
    buf_ += '"';
    need_comma_ = true;
}
void JsonBuilder::value_string(const std::string& v) { value_string(v.c_str()); }
void JsonBuilder::value_string_null() {
    if (need_comma_) buf_ += ',';
    buf_ += "null";
    need_comma_ = true;
}
void JsonBuilder::value_int(int64_t v) {
    if (need_comma_) buf_ += ',';
    char tmp[32];
    std::snprintf(tmp, sizeof(tmp), "%lld", (long long)v);
    buf_ += tmp;
    need_comma_ = true;
}
void JsonBuilder::value_double(double v) {
    if (need_comma_) buf_ += ',';
    char tmp[64];
    std::snprintf(tmp, sizeof(tmp), "%g", v);
    buf_ += tmp;
    need_comma_ = true;
}
void JsonBuilder::value_bool(bool v) {
    if (need_comma_) buf_ += ',';
    buf_ += v ? "true" : "false";
    need_comma_ = true;
}
void JsonBuilder::comma() {
    if (!need_comma_) buf_ += ',';
    need_comma_ = true;
}

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
                              const std::string& quality_check) {
    JsonBuilder j;
    const char* decision_str = "REJECTED";
    switch (decision) {
        case YALLA_EDITION_READY: decision_str = "READY"; break;
        case YALLA_EDITION_READY_WITH_WARNINGS: decision_str = "READY_WITH_WARNINGS"; break;
        case YALLA_EDITION_NEEDS_REVIEW: decision_str = "NEEDS_REVIEW"; break;
        default: decision_str = "REJECTED"; break;
    }

    j.begin_object();
    j.key("schema_version"); j.value_string(schema_version);
    j.key("status"); j.value_string(decision_str);

    j.key("article"); j.begin_object();
    j.key("headline");
    if (article.headline.empty()) j.value_string_null(); else j.value_string(article.headline);
    j.key("subtitle");
    if (article.subtitle.empty()) j.value_string_null(); else j.value_string(article.subtitle);
    j.key("introduction"); j.value_string(article.introduction);
    j.key("body"); j.begin_array();
    for (const auto& [heading, text] : article.body) {
        j.begin_object();
        j.key("heading");
        if (heading.empty()) j.value_string_null(); else j.value_string(heading);
        j.key("text"); j.value_string(text);
        j.key("fact_ids"); j.begin_array();
        j.end_array();
        j.end_object();
    }
    j.end_array();
    j.key("conclusion"); j.value_string(article.conclusion);
    j.key("language"); j.value_string(article.language);
    j.key("article_type"); j.value_string(article.article_type);
    j.end_object();

    j.key("editorial"); j.begin_object();
    j.key("angle"); j.value_string(plan.angle);
    j.key("warnings"); j.begin_array();
    for (const auto& w : warnings) j.value_string(w);
    j.end_array();
    j.end_object();

    j.key("provenance"); j.begin_object();
    j.key("source_ids"); j.begin_array();
    for (const auto& s : source_ids) j.value_string(s);
    j.end_array();
    j.key("fact_count"); j.value_int(fact_count);
    j.key("supported_claim_count"); j.value_int(supported_count);
    j.key("unsupported_claim_count"); j.value_int(unsupported_count);
    j.end_object();

    j.key("validation"); j.begin_object();
    j.key("fact_check"); j.value_string(fact_check);
    j.key("similarity_check"); j.value_string(similarity_check);
    j.key("quality_check"); j.value_string(quality_check);
    j.end_object();

    j.end_object();
    return j.str();
}

} // namespace yalla
