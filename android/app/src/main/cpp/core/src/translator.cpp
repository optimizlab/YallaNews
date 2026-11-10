#include "yalla_core.h"
#include <string>
#include <vector>
#include <sstream>
#include <unordered_map>

struct YallaTranslator {
    YallaInferenceEngineHandle engine;

    std::string language_name(YallaLanguage lang) {
        switch (lang) {
            case YALLA_LANG_ARABIC: return "Arabic";
            case YALLA_LANG_FRENCH: return "French";
            case YALLA_LANG_ENGLISH: return "English";
            default: return "English";
        }
    }

    std::string language_code(YallaLanguage lang) {
        switch (lang) {
            case YALLA_LANG_ARABIC: return "ar";
            case YALLA_LANG_FRENCH: return "fr";
            case YALLA_LANG_ENGLISH: return "en";
            default: return "en";
        }
    }

    std::string build_prompt(const std::string& text, YallaLanguage source, YallaLanguage target) {
        std::string src_name = language_name(source);
        std::string tgt_name = language_name(target);
        std::string src_code = language_code(source);
        std::string tgt_code = language_code(target);

        // Specialized prompts for each language pair
        if (source == YALLA_LANG_ARABIC && target == YALLA_LANG_ENGLISH) {
            return R"(Translate the following Arabic text to English. Preserve names, numbers, and formatting:

Arabic: )" + text + R"(

English:)";
        } else if (source == YALLA_LANG_ENGLISH && target == YALLA_LANG_ARABIC) {
            return R"(ترجم النص التالي من الإنجليزية إلى العربية. احتفظ بالأسماء والأرقام والتنسيق:

English: )" + text + R"(

Arabic:)";
        } else if (source == YALLA_LANG_ARABIC && target == YALLA_LANG_FRENCH) {
            return R"(Traduisez le texte arabe suivant en français. Préservez les noms, nombres et formatage :

Arabe : )" + text + R"(

Français :)";
        } else if (source == YALLA_LANG_FRENCH && target == YALLA_LANG_ARABIC) {
            return R"(ترجم النص التالي من الفرنسية إلى العربية. احتفظ بالأسماء والأرقام والتنسيق:

Français : )" + text + R"(

Arabe :)";
        } else if (source == YALLA_LANG_ENGLISH && target == YALLA_LANG_FRENCH) {
            return R"(Translate the following English text to French. Preserve names, numbers, and formatting:

English: )" + text + R"(

French:)";
        } else if (source == YALLA_LANG_FRENCH && target == YALLA_LANG_ENGLISH) {
            return R"(Translate the following French text to English. Preserve names, numbers, and formatting:

French: )" + text + R"(

English:)";
        }

        // Generic fallback
        return "Translate the following text from " + src_name + " to " + tgt_name + ":\n\n" + text + "\n\nTranslation:";
    }

    std::string build_batch_prompt(const std::vector<std::string>& texts,
                                   YallaLanguage source, YallaLanguage target) {
        std::string src_name = language_name(source);
        std::string tgt_name = language_name(target);

        std::ostringstream oss;
        oss << "Translate the following " << texts.size() << " texts from " << src_name << " to " << tgt_name
            << ". Return as JSON array of translations:\n\n";

        for (size_t i = 0; i < texts.size(); ++i) {
            oss << (i + 1) << ". " << texts[i] << "\n";
        }
        oss << "\nTranslations (JSON array):";
        return oss.str();
    }
};

extern "C" {

YALLA_CORE_EXPORT YallaTranslatorHandle yalla_translator_create(YallaInferenceEngineHandle engine) {
    if (!engine) return nullptr;
    auto* translator = new YallaTranslator();
    translator->engine = engine;
    return translator;
}

YALLA_CORE_EXPORT void yalla_translator_destroy(YallaTranslatorHandle handle) {
    if (handle) delete static_cast<YallaTranslator*>(handle);
}

YALLA_CORE_EXPORT const char* yalla_translator_translate(YallaTranslatorHandle handle,
    const char* text, YallaLanguage source_lang, YallaLanguage target_lang) {
    if (!handle || !text) return strdup("");
    if (source_lang == target_lang) return strdup(text);

    auto* translator = static_cast<YallaTranslator*>(handle);
    std::string t(text);

    std::string prompt = translator->build_prompt(t, source_lang, target_lang);

    YallaInferenceRequest request{};
    request.prompt = prompt.c_str();
    request.max_tokens = static_cast<int32_t>(t.size() * 2);
    request.temperature = 0.1f;
    request.top_p = 0.9f;
    request.stream = false;

    YallaInferenceResponse response = yalla_inference_engine_infer(translator->engine, &request);

    return response.text ? response.text : strdup("");
}

YALLA_CORE_EXPORT const char* yalla_translator_translate_batch(YallaTranslatorHandle handle,
    const char** texts, int32_t count, YallaLanguage source_lang, YallaLanguage target_lang) {
    if (!handle || !texts || count <= 0) return strdup("{\"translations\":[]}");
    if (source_lang == target_lang) {
        // Just return original texts
        std::ostringstream oss;
        oss << "{\"translations\":[";
        for (int i = 0; i < count; ++i) {
            if (i > 0) oss << ",";
            oss << "\"" << (texts[i] ? texts[i] : "") << "\"";
        }
        oss << "]}";
        return strdup(oss.str().c_str());
    }

    auto* translator = static_cast<YallaTranslator*>(handle);
    std::vector<std::string> text_vec;
    for (int i = 0; i < count; ++i) {
        text_vec.push_back(texts[i] ? texts[i] : "");
    }

    std::string prompt = translator->build_batch_prompt(text_vec, source_lang, target_lang);

    YallaInferenceRequest request{};
    request.prompt = prompt.c_str();
    request.max_tokens = count * 100;
    request.temperature = 0.1f;
    request.top_p = 0.9f;
    request.stream = false;

    YallaInferenceResponse response = yalla_inference_engine_infer(translator->engine, &request);

    return response.text ? response.text : strdup("{\"translations\":[]}");
}

} // extern "C"