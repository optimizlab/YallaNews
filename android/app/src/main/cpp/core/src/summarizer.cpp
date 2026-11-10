#include "yalla_core.h"
#include <string>
#include <vector>
#include <sstream>

struct YallaSummarizer {
    YallaInferenceEngineHandle engine;

    std::string build_prompt(const std::string& title, const std::string& content,
                           const std::string& language, int32_t max_length, bool is_batch = false) {
        std::string lang_name;
        std::string prompt_template;

        if (language == "ar" || language == "arabic") {
            lang_name = "Arabic";
            prompt_template = R"(لخص المقالة الإخبارية التالية باللغة العربية في {max_len} كلمة أو أقل:

العنوان: {title}

المحتوى: {content}

الملخص:)";
        } else if (language == "fr" || language == "french") {
            lang_name = "French";
            prompt_template = R"(Résumez l'article de nouvelles suivant en français en {max_len} mots ou moins :

Titre : {title}

Contenu : {content}

Résumé :)";
        } else {
            lang_name = "English";
            prompt_template = R"(Summarize the following English news article in {max_len} words or less:

Title: {title}

Content: {content}

Summary:)";
        }

        std::string prompt = prompt_template;
        size_t pos = prompt.find("{max_len}");
        if (pos != std::string::npos) prompt.replace(pos, 9, std::to_string(max_length));
        pos = prompt.find("{title}");
        if (pos != std::string::npos) prompt.replace(pos, 7, title);
        pos = prompt.find("{content}");
        if (pos != std::string::npos) prompt.replace(pos, 9, content);

        return prompt;
    }

    std::string build_batch_prompt(const std::vector<std::string>& titles,
                                   const std::vector<std::string>& contents,
                                   const std::string& language, int32_t max_length) {
        std::string lang_instruction;
        if (language == "ar" || language == "arabic") {
            lang_instruction = "لخص كل مقالة من المقالات التالية باللغة العربية في " + std::to_string(max_length) + " كلمة أو أقل. أرجع النتيجة كقائمة JSON.";
        } else if (language == "fr" || language == "french") {
            lang_instruction = "Résumez chacun des articles suivants en français en " + std::to_string(max_length) + " mots ou moins. Retournez le résultat sous forme de liste JSON.";
        } else {
            lang_instruction = "Summarize each of the following articles in English in " + std::to_string(max_length) + " words or less. Return as JSON list.";
        }

        std::ostringstream oss;
        oss << lang_instruction << "\n\n";
        for (size_t i = 0; i < titles.size() && i < contents.size(); ++i) {
            oss << "Article " << (i + 1) << ":\n";
            oss << "Title: " << titles[i] << "\n";
            oss << "Content: " << contents[i].substr(0, 2000) << "\n\n";
        }
        oss << "Summaries (JSON array):";
        return oss.str();
    }
};

extern "C" {

YALLA_CORE_EXPORT YallaSummarizerHandle yalla_summarizer_create(YallaInferenceEngineHandle engine) {
    if (!engine) return nullptr;
    auto* summarizer = new YallaSummarizer();
    summarizer->engine = engine;
    return summarizer;
}

YALLA_CORE_EXPORT void yalla_summarizer_destroy(YallaSummarizerHandle handle) {
    if (handle) delete static_cast<YallaSummarizer*>(handle);
}

YALLA_CORE_EXPORT const char* yalla_summarizer_summarize(YallaSummarizerHandle handle,
    const char* title, const char* content, const char* language, int32_t max_length) {
    if (!handle || !title || !content) return strdup("");
    auto* summarizer = static_cast<YallaSummarizer*>(handle);

    std::string t(title), c(content), lang(language ? language : "en");
    int len = max_length > 0 ? max_length : 150;

    std::string prompt = summarizer->build_prompt(t, c, lang, len);

    YallaInferenceRequest request{};
    request.prompt = prompt.c_str();
    request.max_tokens = len * 2;
    request.temperature = 0.3f;
    request.top_p = 0.9f;
    request.stream = false;

    YallaInferenceResponse response = yalla_inference_engine_infer(summarizer->engine, &request);

    const char* result = response.text ? response.text : "";
    return result;
}

YALLA_CORE_EXPORT const char* yalla_summarizer_summarize_batch(YallaSummarizerHandle handle,
    const char** titles, const char** contents, int32_t count, const char* language, int32_t max_length) {
    if (!handle || !titles || !contents || count <= 0) return strdup("{\"summaries\":[]}");

    auto* summarizer = static_cast<YallaSummarizer*>(handle);

    std::vector<std::string> t_vec, c_vec;
    for (int i = 0; i < count; ++i) {
        t_vec.push_back(titles[i] ? titles[i] : "");
        c_vec.push_back(contents[i] ? contents[i] : "");
    }

    std::string lang(language ? language : "en");
    int len = max_length > 0 ? max_length : 150;

    std::string prompt = summarizer->build_batch_prompt(t_vec, c_vec, lang, len);

    YallaInferenceRequest request{};
    request.prompt = prompt.c_str();
    request.max_tokens = count * len * 2;
    request.temperature = 0.3f;
    request.top_p = 0.9f;
    request.stream = false;

    YallaInferenceResponse response = yalla_inference_engine_infer(summarizer->engine, &request);

    const char* result = response.text ? response.text : "{\"summaries\":[]}";
    return result;
}

} // extern "C"