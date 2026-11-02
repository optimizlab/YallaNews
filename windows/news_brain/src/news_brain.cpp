#ifndef NEWSBRAIN_EXPORTS
#define NEWSBRAIN_EXPORTS
#endif
#include "../include/news_brain.h"
#include "../include/page_scanner.h"
#include "../include/article_brain.h"
#include "../include/article_rebuilder.h"
#include "../include/http_fetcher.h"
#include "../../../windows/yalla_engine/arabic_nlp.h"
#include <cstring>
#include <iostream>
#include <sstream>
#include <cmath>
#include <algorithm>
#include <cctype>

using namespace newsbrain;

static char* duplicateString(const std::string& str) {
    char* copy = new char[str.length() + 1];
    std::strcpy(copy, str.c_str());
    return copy;
}

extern "C" {

NEWSBRAIN_EXPORT const char* newsbrain_get_version() {
    return "1.0.0-newsbrain";
}

NEWSBRAIN_EXPORT void newsbrain_free_string(const char* str) {
    if (str != nullptr) {
        delete[] str;
    }
}

NEWSBRAIN_EXPORT void newsbrain_set_http_fetcher(NewsBrainHttpFetchCallback callback) {
    HttpFetcher::instance().setExternalFetcher(callback);
}

NEWSBRAIN_EXPORT const char* newsbrain_scan_url(const char* url) {
    if (url == nullptr) return nullptr;
    try {
        PageScanner scanner;
        PageSkeleton skeleton = scanner.scan(url);
        std::string jsonStr = skeleton.toJson().dump(2);
        return duplicateString(jsonStr);
    } catch (const std::exception& e) {
        std::cerr << "[newsBrain] Error in newsbrain_scan_url: " << e.what() << std::endl;
        return duplicateString("{\"error\": \"" + std::string(e.what()) + "\"}");
    } catch (...) {
        return duplicateString("{\"error\": \"Unknown error during scan_url\"}");
    }
}

NEWSBRAIN_EXPORT const char* newsbrain_scan_html(const char* html, const char* url) {
    if (html == nullptr) return nullptr;
    try {
        std::string urlStr = (url != nullptr) ? url : "";
        PageScanner scanner;
        PageSkeleton skeleton = scanner.scanHtml(html, urlStr);
        std::string jsonStr = skeleton.toJson().dump(2);
        return duplicateString(jsonStr);
    } catch (const std::exception& e) {
        std::cerr << "[newsBrain] Error in newsbrain_scan_html: " << e.what() << std::endl;
        return duplicateString("{\"error\": \"" + std::string(e.what()) + "\"}");
    } catch (...) {
        return duplicateString("{\"error\": \"Unknown error during scan_html\"}");
    }
}

NEWSBRAIN_EXPORT const char* newsbrain_extract_article_url(const char* url) {
    if (url == nullptr) return nullptr;
    try {
        PageScanner scanner;
        PageSkeleton skeleton = scanner.scan(url);

        std::vector<ClassifiedNode> classifiedNodes;
        if (!skeleton.candidates.empty()) {
            ArticleBrain brain;
            classifiedNodes = brain.classifyCandidateNodes(skeleton, skeleton.candidates[0]);
        }

        ArticleRebuilder rebuilder;
        NewsArticle article = rebuilder.rebuild(skeleton, classifiedNodes);
        std::string jsonStr = article.toJson().dump(2);
        return duplicateString(jsonStr);
    } catch (const std::exception& e) {
        std::cerr << "[newsBrain] Error in newsbrain_extract_article_url: " << e.what() << std::endl;
        return duplicateString("{\"error\": \"" + std::string(e.what()) + "\"}");
    } catch (...) {
        return duplicateString("{\"error\": \"Unknown error during extract_article_url\"}");
    }
}

NEWSBRAIN_EXPORT const char* newsbrain_extract_article_html(const char* html, const char* url) {
    if (html == nullptr) return nullptr;
    try {
        std::string urlStr = (url != nullptr) ? url : "";
        PageScanner scanner;
        PageSkeleton skeleton = scanner.scanHtml(html, urlStr);

        std::vector<ClassifiedNode> classifiedNodes;
        if (!skeleton.candidates.empty()) {
            ArticleBrain brain;
            classifiedNodes = brain.classifyCandidateNodes(skeleton, skeleton.candidates[0]);
        }

        ArticleRebuilder rebuilder;
        NewsArticle article = rebuilder.rebuild(skeleton, classifiedNodes);
        std::string jsonStr = article.toJson().dump(2);
        return duplicateString(jsonStr);
    } catch (const std::exception& e) {
        std::cerr << "[newsBrain] Error in newsbrain_extract_article_html: " << e.what() << std::endl;
        return duplicateString("{\"error\": \"" + std::string(e.what()) + "\"}");
    } catch (...) {
        return duplicateString("{\"error\": \"Unknown error during extract_article_html\"}");
    }
}

// Helper: build a simple JSON object with NLP results using nlohmann::json if available,
// otherwise manual string concatenation.
static std::string build_nlp_json(const std::string& category,
                                  const std::string& subcategory,
                                  double sentiment,
                                  const std::string& event_type,
                                  const std::vector<std::string>& keywords,
                                  const std::vector<NerEntity>& entities,
                                  double confidence) {
    std::ostringstream oss;
    oss << "{";
    oss << "\"category\":\"" << category << "\",";
    oss << "\"subcategory\":\"" << subcategory << "\",";
    oss << "\"sentiment\":" << sentiment << ",";
    oss << "\"event_type\":\"" << event_type << "\",";
    oss << "\"confidence\":" << confidence << ",";
    oss << "\"keywords\":[";
    for (size_t i = 0; i < keywords.size(); ++i) {
        if (i) oss << ",";
        oss << "\"" << keywords[i] << "\"";
    }
    oss << "],";
    oss << "\"entities\":[";
    for (size_t i = 0; i < entities.size(); ++i) {
        if (i) oss << ",";
        oss << "{\"type\":\"" << entities[i].type << "\",";
        oss << "\"value\":\"" << entities[i].value << "\",";
        oss << "\"canonical\":\"" << entities[i].canonical << "\",";
        oss << "\"confidence\":" << entities[i].confidence << "}";
    }
    oss << "]";
    oss << "}";
    return oss.str();
}

NEWSBRAIN_EXPORT const char* newsbrain_classify_article(const char* title, const char* content, const char* summary) {
    if (title == nullptr) return duplicateString("{\"category\":\"general\",\"subcategory\":\"general\",\"sentiment\":0.0,\"event_type\":\"general\",\"confidence\":0.0,\"keywords\":[],\"entities\":[]}");
    std::string t = (title != nullptr) ? title : "";
    std::string c = (content != nullptr) ? content : "";
    std::string s = (summary != nullptr) ? summary : "";
    try {
        AnalysisResult res = analyze_article_nlp(t, c, s);
        std::string json = build_nlp_json(res.category, res.subcategory, res.sentiment, res.event_type, res.keywords, res.entities, res.confidence);
        return duplicateString(json);
    } catch (const std::exception& e) {
        std::cerr << "[newsBrain] Error in newsbrain_classify_article: " << e.what() << std::endl;
        return duplicateString("{\"category\":\"general\",\"subcategory\":\"general\",\"sentiment\":0.0,\"event_type\":\"general\",\"confidence\":0.0,\"keywords\":[],\"entities\":[]}");
    } catch (...) {
        return duplicateString("{\"category\":\"general\",\"subcategory\":\"general\",\"sentiment\":0.0,\"event_type\":\"general\",\"confidence\":0.0,\"keywords\":[],\"entities\":[]}");
    }
}

NEWSBRAIN_EXPORT const char* newsbrain_classify_category(const char* title, const char* content, const char* summary) {
    if (title == nullptr) return duplicateString("general");
    std::string t = (title != nullptr) ? title : "";
    std::string c = (content != nullptr) ? content : "";
    std::string s = (summary != nullptr) ? summary : "";
    try {
        double confidence = 0.0;
        std::string category = classify_category(t, c, s, confidence);
        return duplicateString(category);
    } catch (const std::exception& e) {
        std::cerr << "[newsBrain] Error in newsbrain_classify_category: " << e.what() << std::endl;
        return duplicateString("general");
    } catch (...) {
        return duplicateString("general");
    }
}

NEWSBRAIN_EXPORT double newsbrain_analyze_sentiment(const char* text) {
    if (text == nullptr) return 0.0;
    try {
        return analyze_sentiment(text);
    } catch (...) {
        return 0.0;
    }
}

NEWSBRAIN_EXPORT double newsbrain_score_article_quality(const char* title, const char* content, const char* summary) {
    const std::string t = title ? title : "";
    const std::string c = content ? content : "";
    const std::string s = summary ? summary : "";
    std::string all = t + " " + s + " " + c;
    std::string lower = all;
    std::transform(lower.begin(), lower.end(), lower.begin(), [](unsigned char ch) { return static_cast<char>(std::tolower(ch)); });

    double score = 0.0;
    if (t.size() >= 25) score += 0.25;
    if (s.size() >= 35) score += 0.15;
    if (c.size() >= 180) score += 0.35;
    if (c.size() >= 500) score += 0.10;
    if (all.find(".") != std::string::npos || all.find("؟") != std::string::npos) score += 0.10;

    const char* blocked[] = {
      "privacy policy", "terms of use", "terms and conditions", "cookie policy",
      "login", "sign in", "register", "subscribe", "advertisement", "sponsored",
      "شروط الاستخدام", "سياسة الخصوصية", "سياسة الاستخدام", "تسجيل الدخول",
      "اشترك", "إعلان", "إعلانات", "ملفات تعريف الارتباط"
    };
    for (const auto* marker : blocked) {
        if (lower.find(marker) != std::string::npos) score -= 0.35;
    }
    if (t.size() < 18 || c.size() < 80) score -= 0.35;
    return std::max(0.0, std::min(1.0, score));
}

} // extern "C"
