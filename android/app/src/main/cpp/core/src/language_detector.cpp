// Language Detector - Stub implementation
#include "yalla_core.h"
#include <string>
#include <algorithm>
#include <cctype>

struct YallaLanguageDetector {
    YallaLanguageDetector() = default;
};

extern "C" {

YALLA_CORE_EXPORT YallaLanguageDetectorHandle yalla_language_detector_create() {
    return new YallaLanguageDetector();
}

YALLA_CORE_EXPORT void yalla_language_detector_destroy(YallaLanguageDetectorHandle handle) {
    if (handle) delete static_cast<YallaLanguageDetector*>(handle);
}

YALLA_CORE_EXPORT YallaLanguage yalla_language_detector_detect(YallaLanguageDetectorHandle handle,
    const char* text, float* confidence) {
    if (!handle || !text) {
        if (confidence) *confidence = 0.0f;
        return YALLA_LANG_UNKNOWN;
    }
    auto* detector = static_cast<YallaLanguageDetector*>(handle);
    std::string textStr(text);
    std::transform(textStr.begin(), textStr.end(), textStr.begin(),
        [](unsigned char c) { return std::tolower(c); });
    if (textStr.find("arabic") != std::string::npos ||
        textStr.find("العربية") != std::string::npos) {
        if (confidence) *confidence = 0.8f;
        return YALLA_LANG_ARABIC;
    }
    if (textStr.find("french") != std::string::npos ||
        textStr.find("français") != std::string::npos ||
        textStr.find("français") != std::string::npos) {
        if (confidence) *confidence = 0.8f;
        return YALLA_LANG_FRENCH;
    }
    if (confidence) *confidence = 0.8f;
    return YALLA_LANG_ENGLISH;
}

YALLA_CORE_EXPORT const char* yalla_language_detector_normalize(YallaLanguageDetectorHandle handle,
    YallaLanguage lang, const char* text) {
    if (!handle || !text) return strdup("");
    auto* detector = static_cast<YallaLanguageDetector*>(handle);
    std::string result(text);
    if (lang == YALLA_LANG_ARABIC) {
        // Simple Arabic normalization - remove diacritics
        std::string arabic_result;
        for (size_t i = 0; text[i] != '\0'; ++i) {
            char c = text[i];
            if ((unsigned char)c >= 0x60 && (unsigned char)c <= 0x7A) {
                arabic_result += std::tolower(c);
            } else if ((unsigned char)c >= 0x600 && (unsigned char)c <= 0x6FF) {
                arabic_result += c;
            }
        }
        return strdup(arabic_result.c_str());
    }
    std::transform(result.begin(), result.end(), result.begin(),
        [](unsigned char c) { return std::tolower(c); });
    return strdup(result.c_str());
}

} // extern "C"
