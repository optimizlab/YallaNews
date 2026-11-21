#include "hybrid_intelligence.h"

#include <algorithm>
#include <cctype>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <iostream>
#include <new>
#include <set>
#include <sstream>
#include <string>

namespace newsbrain {

HybridIntelligenceEngine::HybridIntelligenceEngine(
    const HybridIntelligenceConfig& config)
    : config_(config),
      knowledge_version_("kb.v1.0"),
      healthy_(true) {
    if (config.working_memory_bytes < 1024 * 1024) {
        healthy_ = false;
    }
    if (config.enable_tiny_llm && config.model_path.empty()) {
        config_.enable_tiny_llm = false;
    }
}

HybridIntelligenceEngine::~HybridIntelligenceEngine() = default;

HybridIntelligenceResult HybridIntelligenceEngine::process(
    const std::string& title,
    const std::string& body,
    const std::string& summary,
    const std::string& url,
    const std::string& language,
    const std::string& source_id,
    const std::string& published_date,
    const std::vector<std::string>& prior_article_ids,
    const std::vector<std::string>& prior_event_ids) {

    auto start = std::chrono::high_resolution_clock::now();
    trace_.clear();

    HybridIntelligenceResult result;

    result = pass1_CppPreprocessing(title, body, summary, url, language);
    if (result.decision == NewsDecision::REJECT && !result.validation.rejection_reasons.empty()) {
        auto end = std::chrono::high_resolution_clock::now();
        result.processing_time_ms = std::chrono::duration<double, std::milli>(end - start).count();
        result.explainability = buildExplainability(result);
        return result;
    }

    result = pass2_PhpRules(result, title, body);
    result = pass3_PreliminaryScore(result);

    if (config_.enable_tiny_llm && result.tiny_llm_invoked < config_.max_tiny_llm_calls_per_job) {
        result = pass4_TinyLlmSemantic(result, title, body, summary);
    }

    result = pass5_CppValidation(result);
    result = pass6_FinalDecision(result);
    result = pass7_StoreFeedback(result, source_id);

    auto end = std::chrono::high_resolution_clock::now();
    result.processing_time_ms = std::chrono::duration<double, std::milli>(end - start).count();
    result.explainability = buildExplainability(result);
    result.knowledge_version = knowledge_version_;

    return result;
}

HybridIntelligenceResult HybridIntelligenceEngine::pass1_CppPreprocessing(
    const std::string& title,
    const std::string& body,
    const std::string& summary,
    const std::string& url,
    const std::string& language) {

    HybridIntelligenceResult result;
    addTrace("PASS1", "Starting C++ processing");

    if (title.empty() || title.length() < 5) {
        result.validation.rejection_reasons.push_back("Title empty or too short");
        result.decision = NewsDecision::REJECT;
        return result;
    }

    std::string title_lower = title;
    std::transform(title_lower.begin(), title_lower.end(), title_lower.begin(),
                   [](unsigned char c){ return std::tolower(c); });

    const char* generic_titles[] = {
        "news", "latest", "breaking", "home", "accueil", "principal",
        "politics", "politique", "sports", "sport", "economy", "économie",
        "business", "international", "world", "monde", "technology",
        "technologie", "culture", "health", "santé", "science",
        "regions", "régions", "local", "national", "society", "société"
    };
    for (const char* gt : generic_titles) {
        if (title_lower == gt) {
            result.validation.rejection_reasons.push_back(
                "Generic single-word title: " + std::string(gt));
            result.decision = NewsDecision::REJECT;
            return result;
        }
    }

    const char* site_only[] = {
        "al jazeera", "الجزيرة", "bbc", "cnn", "reuters", "le monde",
        "hespress", "mosaique fm", "almasryalyoum", "alarabiya",
        "sky news", "france 24", "dw", "ap news", "afp"
    };
    for (const char* so : site_only) {
        if (title_lower == so) {
            result.validation.rejection_reasons.push_back(
                "Site-name-only title: " + std::string(so));
            result.decision = NewsDecision::REJECT;
            return result;
        }
    }

    bool has_arabic = false, has_cjk = false, has_cyrillic = false;
    for (size_t i = 0; i < title.size(); ++i) {
        unsigned char c = (unsigned char)title[i];
        if (c == 0xD8 || c == 0xD9) { has_arabic = true; i++; }
        else if (c >= 0xE0 && c <= 0xEF) { has_cjk = true; i += 2; }
        else if (c >= 0xC0 && c <= 0xDF) { has_cyrillic = true; i++; }
    }
    int script_count = (has_arabic ? 1 : 0) + (has_cjk ? 1 : 0) + (has_cyrillic ? 1 : 0);
    if (script_count > 1) {
        result.validation.rejection_reasons.push_back("Mixed-script title (scraping artifact)");
        result.decision = NewsDecision::REJECT;
        return result;
    }

    if (body.empty() || body.length() < 40) {
        result.validation.rejection_reasons.push_back("Body empty or too short (<40 chars)");
        result.decision = NewsDecision::REJECT;
        return result;
    }

    int real_words = 0;
    std::string word;
    for (char c : body) {
        if (std::isalpha((unsigned char)c)) {
            word += c;
        } else {
            if (word.length() > 2) real_words++;
            word.clear();
        }
    }
    if (word.length() > 2) real_words++;

    if (real_words < 5) {
        result.validation.rejection_reasons.push_back("Too few real words (<5)");
        result.decision = NewsDecision::REJECT;
        return result;
    }

    int sentence_enders = 0;
    for (char c : body) {
        if (c == '.' || c == '!' || c == '?' || c == '؟' || c == '۔') sentence_enders++;
    }
    if (sentence_enders < 1 && body.length() > 200) {
        result.validation.rejection_reasons.push_back("No sentence structure");
        result.decision = NewsDecision::REJECT;
        return result;
    }

    std::string body_lower = body;
    std::transform(body_lower.begin(), body_lower.end(), body_lower.begin(),
                   [](unsigned char c){ return std::tolower(c); });

    const char* boilerplate[] = {
        "cookie", "cookies", "privacy policy", "politique de confidentialité",
        "mentions légales", "terms of service", "conditions générales",
        "about us", "à propos", "contact us", "contactez-nous",
        "newsletter", "subscribe", "abonnement", "inscrivez-vous",
        "advertisement", "publicité", "sponsored", "contenu sponsorisé",
        "follow us", "suivez-nous", "rejoignez-nous",
        "app store", "google play", "téléchargez notre",
        "all rights reserved", "tous droits réservés",
        "copyright", "droits d’auteur", "powered by"
    };
    int boilerplate_hits = 0;
    for (const char* bp : boilerplate) {
        if (body_lower.find(bp) != std::string::npos) boilerplate_hits++;
    }
    double boilerplate_ratio = (real_words > 0)
        ? (double)boilerplate_hits / std::max(1.0, (double)real_words / 10.0)
        : 1.0;
    if (boilerplate_ratio > 0.5) {
        result.validation.rejection_reasons.push_back(
            "Content appears to be boilerplate/nav/ads");
        result.decision = NewsDecision::REJECT;
        return result;
    }

    result.validation.language_ok = true;
    result.validation.extraction_ok = true;

    static const char* event_kws[] = {
        "announced", "declared", "launched", "signed", "agreed", "decided",
        "elected", "appointed", "resigned", "died", "killed", "injured",
        "attacked", "arrested", "charged", "convicted", "sentenced",
        "approved", "rejected", "passed", "vetoed", "ratified",
        "won", "lost", "defeated", "beat", "scored", "qualified",
        "crashed", "exploded", "burned", "flooded", "earthquake",
        "protested", "demonstrated", "striked", "boycotted",
        "invested", "acquired", "merged", "split", "laid off",
        "a annoncé", "a déclaré", "a lancé", "a signé", "a décidé",
        "أعلن", "أعلنت", "أطلق", "وقع", "اتفق", "قرر", "عين",
        "استقال", "توفي", "قُتل", "أصيب", "هاجم", "اعتقل",
        "أُحيلا", "أُدين", "حكم", "أُقر", "أُرفض",
        "فاز", "خسر", "انهزم", "انهزمت", "سجل", "تأهل",
        "انفجر", "احترق", "غرق", "زلزل", "تظاهر", "اعتصم",
        "أضرب", "قاطع", "استثمر", "اشترى", "اندمج", "انفصل",
        "أقال", "moindre", "dévoilé", "présenté", "lancé"
    };

    std::string combined = title + " " + body + " " + summary;
    std::string combined_lower = combined;
    std::transform(combined_lower.begin(), combined_lower.end(), combined_lower.begin(),
                   [](unsigned char c){ return std::tolower(c); });

    int event_kw_count = 0;
    for (const char* kw : event_kws) {
        if (combined_lower.find(kw) != std::string::npos) {
            event_kw_count++;
        }
    }

    result.validation.has_event_evidence = (event_kw_count > 0);
    result.validation.is_real_news = (event_kw_count > 0) && (real_words >= 10);

    result.event.action = "";
    result.event.subject = "";
    result.event.object = "";
    result.event.confidence = 0.0;

    const char* action_verbs[] = {
        "announced", "declared", "launched", "signed", "agreed", "decided",
        "elected", "appointed", "resigned", "approved", "rejected",
        "passed", "vetoed", "ratified", "won", "lost", "defeated",
        "crashed", "exploded", "burned", "flooded", "protested",
        "invested", "acquired", "merged", "struck", "hit"
    };
    for (const char* av : action_verbs) {
        size_t pos = combined_lower.find(av);
        if (pos != std::string::npos) {
            result.event.action = av;
            result.event.confidence = 0.7;
            break;
        }
    }

    result.scores.news_signal_score = result.validation.is_real_news ? 0.7 : 0.2;
    result.scores.extraction_confidence = 0.8;
    double aq_score = (double)real_words / 100.0;
    if (aq_score > 1.0) aq_score = 1.0;
    result.scores.article_quality_score = aq_score;

    addTrace("PASS1", "C++ processing complete");
    return result;
}

HybridIntelligenceResult HybridIntelligenceEngine::pass2_PhpRules(
    HybridIntelligenceResult& result,
    const std::string& title,
    const std::string& body) {

    addTrace("PASS2", "Applying PHP-derived rules and dictionaries");

    result.category = classifyCategory(title, body);
    result.scores.importance_score = computeImportance(title, body, result.category);
    result.headline = analyzeHeadline(title, body);
    result.scores.freshness_score = computeFreshness(result.event.event_date);
    result.scores.event_specificity_score = computeEventSpecificity(result.event);
    result.scores.title_body_match_score = computeTitleBodyMatch(title, body);
    result.scores.duplicate_probability = result.duplicate.similarity_score;

    addTrace("PASS2", "PHP-derived rules applied");
    return result;
}

HybridIntelligenceResult HybridIntelligenceEngine::pass3_PreliminaryScore(
    HybridIntelligenceResult& result) {

    addTrace("PASS3", "Preliminary scoring");

    double overall = result.scores.overallScore();

    if (overall < 0.30) {
        result.validation.rejection_reasons.push_back(
            "Overall score too low: " + std::to_string(overall));
        result.decision = NewsDecision::REJECT;
        return result;
    }

    if (!result.validation.has_event_evidence &&
        result.scores.news_signal_score < 0.4) {
        result.validation.rejection_reasons.push_back(
            "No event evidence detected");
        result.decision = NewsDecision::REVIEW;
        return result;
    }

    addTrace("PASS3", "Preliminary scoring complete");
    return result;
}

HybridIntelligenceResult HybridIntelligenceEngine::pass4_TinyLlmSemantic(
    HybridIntelligenceResult& result,
    const std::string& title,
    const std::string& body,
    const std::string& summary) {

    addTrace("PASS4", "TinyLLM semantic analysis");

    if (!config_.enable_tiny_llm) {
        addTrace("PASS4", "TinyLLM disabled, skipping");
        return result;
    }

    double overall = result.scores.overallScore();
    if (overall > 0.80 && result.validation.is_real_news) {
        addTrace("PASS4", "High confidence from deterministic, skipping TinyLLM");
        return result;
    }

    if (result.tiny_llm_invoked >= config_.max_tiny_llm_calls_per_job) {
        addTrace("PASS4", "TinyLLM call limit reached");
        return result;
    }

    std::string prompt = buildTinyLlmPrompt(title, body, summary, result);
    std::string llm_response = invokeTinyLlm(prompt);
    result.tiny_llm_invoked++;

    parseTinyLlmResponse(result, llm_response);

    addTrace("PASS4", "TinyLLM semantic analysis complete");
    return result;
}

HybridIntelligenceResult HybridIntelligenceEngine::pass5_CppValidation(
    HybridIntelligenceResult& result) {

    addTrace("PASS5", "C++ validation of model response");

    if (!result.validation.has_event_evidence &&
        result.semantic_confidence > 0.7) {
        result.semantic_confidence *= 0.5;
        result.validation.warnings.push_back(
            "TinyLLM confidence exceeds deterministic evidence");
    }

    if (result.category.primary_confidence < 0.4) {
        result.validation.warnings.push_back(
            "Low category confidence");
    }

    if (result.scores.freshness_score < 0.3) {
        result.validation.warnings.push_back(
            "Article may be old");
    }

    addTrace("PASS5", "C++ validation complete");
    return result;
}

HybridIntelligenceResult HybridIntelligenceEngine::pass6_FinalDecision(
    HybridIntelligenceResult& result) {

    addTrace("PASS6", "Final NewsBrain decision");

    result.decision = makeDecision(result.scores, result.validation);

    if (result.decision == NewsDecision::ACCEPT &&
        !result.event.new_development.empty() &&
        result.event.is_new_development) {
        result.decision = NewsDecision::NEW_DEVELOPMENT;
    }

    addTrace("PASS6", "Decision: " + std::string(decisionToString(result.decision)));
    return result;
}

HybridIntelligenceResult HybridIntelligenceEngine::pass7_StoreFeedback(
    HybridIntelligenceResult& result,
    const std::string& article_id) {

    addTrace("PASS7", "Storing feedback");

    result.validation.warnings.push_back(
        "Processed through hybrid intelligence pipeline");

    return result;
}

void HybridIntelligenceEngine::addTrace(
    const std::string& step, const std::string& detail) {
    trace_.push_back(step + ": " + detail);
}

NewsDecision HybridIntelligenceEngine::makeDecision(
    const NewsScores& scores, const NewsValidationResult& val) {

    if (!val.is_real_news || !val.extraction_ok) {
        return NewsDecision::REJECT;
    }

    if (!val.has_event_evidence) {
        return NewsDecision::REVIEW;
    }

    double overall = scores.overallScore();

    if (overall >= config_.accept_threshold) {
        return NewsDecision::ACCEPT;
    }
    if (overall >= config_.review_threshold) {
        return NewsDecision::REVIEW;
    }
    return NewsDecision::REJECT;
}

std::string HybridIntelligenceEngine::buildExplainability(
    const HybridIntelligenceResult& r) {

    std::ostringstream oss;
    oss << "NewsBrain Decision: " << decisionToString(r.decision) << "\n";
    oss << "Overall Score: " << r.scores.overallScore() << "\n";
    oss << "News Signal: " << r.scores.news_signal_score << "\n";
    oss << "Event Specificity: " << r.scores.event_specificity_score << "\n";
    oss << "Title/Body Match: " << r.scores.title_body_match_score << "\n";
    oss << "Freshness: " << r.scores.freshness_score << "\n";
    oss << "Importance: " << r.scores.importance_score << "\n";
    oss << "Duplicate Probability: " << r.scores.duplicate_probability << "\n";
    oss << "Category: " << categoryToString(r.category.primary)
        << " (conf: " << r.category.primary_confidence << ")\n";
    oss << "Event: " << r.event.action << " by " << r.event.subject << "\n";
    oss << "Headline Issues: ";
    for (const auto& issue : r.headline.issues) {
        oss << issue << "; ";
    }
    oss << "\n";
    oss << "Rejection Reasons: ";
    for (const auto& reason : r.validation.rejection_reasons) {
        oss << reason << "; ";
    }
    oss << "\n";
    oss << "Warnings: ";
    for (const auto& w : r.validation.warnings) {
        oss << w << "; ";
    }
    oss << "\n";
    oss << "Pipeline: ";
    for (const auto& t : r.pipeline_trace) {
        oss << t << " | ";
    }
    return oss.str();
}

std::string HybridIntelligenceEngine::getLastExplainability() const {
    return buildExplainability(HybridIntelligenceResult{});
}

void HybridIntelligenceEngine::recordFeedback(
    const std::string& article_id,
    NewsDecision original_decision,
    NewsDecision corrected_decision,
    const std::string& correction_reason) {
    addTrace("FEEDBACK", "Article " + article_id + ": " +
        decisionToString(original_decision) + " -> " +
        decisionToString(corrected_decision) + ": " + correction_reason);
}

std::string HybridIntelligenceEngine::getKnowledgeVersion() const {
    return knowledge_version_;
}

bool HybridIntelligenceEngine::isHealthy() const {
    return healthy_;
}

CategoryResult HybridIntelligenceEngine::classifyCategory(
    const std::string& title, const std::string& body) {

    CategoryResult result;
    std::string combined = title + " " + body;
    std::string combined_lower = combined;
    std::transform(combined_lower.begin(), combined_lower.end(), combined_lower.begin(),
                   [](unsigned char c){ return std::tolower(c); });

    struct CategoryKeywords {
        NewsCategory cat;
        std::vector<std::string> keywords;
        double weight;
    };

    std::vector<CategoryKeywords> cats = {
        {NewsCategory::POLITICS, {"president", "minister", "government", "election",
                                  "parliament", "congress", "senate", "law", "bill",
                                  "policy", "diplomat", "embassy", "summit", "treaty",
                                  "الرئيس", "الوزير", "الحكومة", "البرلمان", "الانتخابات",
                                  "président", "ministre", "gouvernement", "élections",
                                  "parlement", "loi", "politique", "diplomate"}, 1.0},
        {NewsCategory::ECONOMY, {"economy", "economic", "market", "stock", "trade",
                                 "business", "company", "investment",
                                 "inflation", "gdp", "budget", "tax", "tariff",
                                 "الاقتصاد", "السوق", "التجارة", "الاستثمار",
                                 "économie", "marché", "commerce", "entreprise",
                                 "investissement", "inflation", "budget"}, 1.0},
        {NewsCategory::SPORT, {"sport", "sports", "football", "soccer", "basketball",
                               "tennis", "match", "game", "team", "player", "coach",
                               "championship", "tournament", "league", "goal", "score",
                               "الرياضة", "كرة القدم", "المباراة", "الفريق", "اللاعب",
                               "sport", "football", "match", "équipe", "joueur",
                               "championnat", "tournoi", "but", "score"}, 1.0},
        {NewsCategory::TECH, {"technology", "tech", "software", "hardware", "computer",
                              "internet", "website", "app", "application", "digital",
                              "data", "ai", "artificial intelligence", "robot", "crypto",
                              "التقنية", "البرمجيات", "الإنترنت", "الموقع",
                              "تكنولوجيا", "البرمجة", "البيانات", "الذكاء الاصطناعي",
                              "technologie", "logiciel", "matériel", "informatique",
                              "internet", "site web", "application", "numérique"}, 1.0},
        {NewsCategory::SCIENCE, {"science", "scientific", "research", "study", "discovery",
                                 "experiment", "scientist", "university", "laboratory",
                                 "البحث", "الدراسة", "الاكتشاف", "العالم", "الجامعة",
                                 "المختبر", "العلوم", "العلمي", "البحث العلمي",
                                 "science", "scientifique", "recherche", "étude",
                                 "découverte", "expérience", "scientifique", "université"}, 1.0},
        {NewsCategory::HEALTH, {"health", "healthcare", "medical", "medicine", "hospital",
                                "doctor", "patient", "disease", "virus", "vaccine",
                                "treatment", "therapy", "clinic", "healthcare",
                                "الصحة", "الرعاية الصحية", "الطبي", "الطب", "المستشفى",
                                "الطبيب", "المريض", "المرض", "الفيروس", "اللقاح",
                                " santé", "santé", "médical", "médecine", "hôpital",
                                "docteur", "patient", "maladie", "virus", "vaccin"}, 1.0},
        {NewsCategory::WORLD, {"world", "international", "global", "foreign", "overseas",
                               "dubai", "london", "paris", "cairo", "beirut", "baghdad",
                               "العالم", "الدولي", "عالمي", "خارجي", "دبي", "لندن",
                               "باريس", "القاهرة", "بيروت", "بغداد",
                               "monde", "international", "global", "étranger"}, 1.0},
        {NewsCategory::CULTURE, {"culture", "cultural", "art", "artist", "museum", "gallery",
                                 "exhibition", "festival", "concert", "theater", "theatre",
                                 "film", "movie", "cinema", "music", "book", "literature",
                                 "الثقافة", "الفن", "الفنان", "المتحف", "المعرض",
                                 "المهرجان", "الحفل", "المسرح", "الفيلم", "السينما",
                                 "الثقافة", "الفن", "الأدب", "الثقافي",
                                 "culture", "culturel", "art", "artiste", "musée",
                                 "exposition", "festival", "concert", "théâtre", "film"}, 1.0},
        {NewsCategory::ISLAMIC, {"islamic", "islam", "mosque", "prayer", "ramadan",
                                 "hajj", "umrah", "quran", "hadith", "imam", "sheikh",
                                 "الإسلام", "الإسلامي", "المسجد", "الصلاة", "رمضان",
                                 "الحج", "العمرة", "القرآن", "الحديث", "الإمام", "الشيخ",
                                 "islam", "islamique", "mosquée", "prière", "ramadan",
                                 "hadj", "omra", "coran", "imam"}, 1.0},
        {NewsCategory::WOMEN, {"women", "woman", "female", "girl", "gender", "feminist",
                               "المرأة", "النساء", "الأنثى", "البنت", "النوع",
                               "femme", "femmes", "féminin", "fille", "genre"}, 1.0},
        {NewsCategory::SOCIETY, {"society", "social", "community", "people", "citizen",
                                 "Crime", "police", "court", "judge", "lawyer",
                                 "المجتمع", "الاجتماعي", "المواطن", "المواطنين",
                                 "الجريمة", "الشرطة", "المحكمة", "القاضي", "المحامي",
                                 "société", "social", "communauté", "citoyen",
                                 "crime", "police", "tribunal", "juge", "avocat"}, 1.0}
    };

    double best_score = 0.0;
    NewsCategory best_cat = NewsCategory::UNKNOWN;

    for (const auto& cat : cats) {
        double score = 0.0;
        int matched = 0;
        for (const auto& kw : cat.keywords) {
            if (combined_lower.find(kw) != std::string::npos) {
                score += cat.weight / (double)cat.keywords.size();
                matched++;
            }
        }
        if (matched > 0 && score > best_score) {
            best_score = score;
            best_cat = cat.cat;
            result.matched_keywords.clear();
            for (const auto& kw : cat.keywords) {
                if (combined_lower.find(kw) != std::string::npos) {
                    result.matched_keywords.push_back(kw);
                }
            }
        }
    }

    result.primary = best_cat;
    if (best_score >= 1.0) {
        result.primary_confidence = 1.0;
    } else {
        result.primary_confidence = best_score;
    }
    if (result.primary_confidence < 0.2) {
        result.primary = NewsCategory::VARIETIES;
        result.primary_confidence = 0.3;
    }

    result.reasoning = "Category classified using keyword dictionaries";
    return result;
}

HeadlineAnalysis HybridIntelligenceEngine::analyzeHeadline(
    const std::string& title, const std::string& body) {

    HeadlineAnalysis ha;
    std::string t_lower = title;
    std::transform(t_lower.begin(), t_lower.end(), t_lower.begin(),
                   [](unsigned char c){ return std::tolower(c); });

    const char* sensational[] = {
        "shocking", "shock", "amazing", "incredible", "unbelievable",
        "miracle", "secret", "hidden", "exposed", "revealed", "scandal",
        "outrage", "furious", "devastating", "tragic", "horrific",
        "amazing", "stunning", "jaw-dropping", "mind-blowing",
        "صادم", "مذهل", "غريب", "مفاجئ", "فضيحة", "غضب", "مأساة", "مروّع",
        "choquant", "incroyable", "secret", "révélé", "scandale"
    };
    int sens_count = 0;
    for (const char* s : sensational) {
        if (t_lower.find(s) != std::string::npos) sens_count++;
    }
    ha.sensationalism_score = std::min(1.0, (double)sens_count / 5.0);
    ha.is_sensational = (ha.sensationalism_score > 0.4);
    if (ha.is_sensational) ha.issues.push_back("Sensational language detected");

    const char* clickbait[] = {
        "you won't believe", "what happened next", "this is why",
        "the truth about", "shocking truth", "you need to see",
        "will change your life", "never seen before", "breaking now",
        "لا تصدق", "ماذا حدث بعد ذلك", "هذه هي الحقيقة", "الحقيقة الصادمة",
        "غيرت حياتك", "لم يسبق له مثيل", "عاجل الآن",
        "vous ne croirez pas", "la vérité sur", "choquant", "incroyable"
    };
    int click_count = 0;
    for (const char* cb : clickbait) {
        if (t_lower.find(cb) != std::string::npos) click_count++;
    }
    ha.clickbait_score = std::min(1.0, (double)click_count / 3.0);
    ha.is_clickbait = (ha.clickbait_score > 0.3);
    if (ha.is_clickbait) ha.issues.push_back("Clickbait pattern detected");

    if (!title.empty() && title.back() == '?') {
        ha.is_question = true;
        ha.issues.push_back("Question-form headline");
    }

    const char* exaggeration[] = {
        "always", "never", "all", "every", "none", "nobody", "everybody",
        "always", "tous", "jamais", "rien", "personne", "tout le monde",
        "constamment", "toujours", "personne", "rien"
    };
    for (const char* ex : exaggeration) {
        if (t_lower.find(ex) != std::string::npos) {
            ha.has_exaggeration = true;
            ha.issues.push_back("Absolute/exaggeration term: " + std::string(ex));
            break;
        }
    }

    if (!body.empty()) {
        std::string body_lower = body;
        std::transform(body_lower.begin(), body_lower.end(), body_lower.begin(),
                       [](unsigned char c){ return std::tolower(c); });

        int title_word_matches = 0;
        int title_word_count = 0;
        std::string word;
        for (char c : title) {
            if (std::isalpha((unsigned char)c)) {
                word += std::tolower((unsigned char)c);
            } else {
                if (word.length() > 3) {
                    title_word_count++;
                    if (body_lower.find(word) != std::string::npos) matched++;
                }
                word.clear();
            }
        }
        if (word.length() > 3) {
            title_word_count++;
            if (body_lower.find(word) != std::string::npos) matched++;
        }

        if (title_word_count > 0) {
            double match_ratio = (double)title_word_matches / (double)title_word_count;
            ha.title_body_mismatch = (match_ratio < 0.3);
            if (ha.title_body_mismatch) {
                ha.issues.push_back("Title words not found in body");
            }
        }
    }

    ha.title_body_match_score = ha.title_body_mismatch ? 0.2 : 0.9;

    if (ha.is_sensational) ha.warnings.push_back("Sensational headline - verify body");
    if (ha.is_clickbait) ha.warnings.push_back("Clickbait headline pattern");
    if (ha.title_body_mismatch) ha.warnings.push_back("Title/body mismatch detected");

    return ha;
}

double HybridIntelligenceEngine::computeImportance(
    const std::string& title, const std::string& body, const CategoryResult& cat) {

    double score = 0.0;

    switch (cat.primary) {
        case NewsCategory::POLITICS: score += 0.25; break;
        case NewsCategory::ECONOMY: score += 0.20; break;
        case NewsCategory::WORLD: score += 0.20; break;
        case NewsCategory::HEALTH: score += 0.20; break;
        case NewsCategory::SCIENCE: score += 0.15; break;
        case NewsCategory::SPORT: score += 0.10; break;
        case NewsCategory::CULTURE: score += 0.10; break;
        case NewsCategory::TECH: score += 0.15; break;
        default: score += 0.05; break;
    }

    if (title.length() > 30) score += 0.1;
    if (title.length() > 60) score += 0.1;

    if (body.length() > 200) score += 0.1;
    if (body.length() > 500) score += 0.1;
    if (body.length() > 1000) score += 0.1;

    int num_count = 0;
    std::string num;
    for (char c : body) {
        if (std::isdigit((unsigned char)c)) {
            num += c;
        } else {
            if (!num.empty() && num.length() >= 2) num_count++;
            num.clear();
        }
    }
    if (!num.empty() && num.length() >= 2) num_count++;
    if (num_count > 0) {
        double num_score = (double)num_count * 0.05;
        if (num_score > 0.2) num_score = 0.2;
        score += num_score;
    }

    if (score > 1.0) score = 1.0;
    return score;
}

double HybridIntelligenceEngine::computeFreshness(const std::string& pub_date) {
    if (pub_date.empty()) return 0.5;
    return 0.7;
}

double HybridIntelligenceEngine::computeEventSpecificity(const DetectedEvent& event) {
    double score = 0.0;
    if (!event.action.empty()) score += 0.2;
    if (!event.subject.empty()) score += 0.2;
    if (!event.object.empty()) score += 0.2;
    if (!event.event_date.empty()) score += 0.2;
    if (!event.new_development.empty()) score += 0.2;
    if (score > 1.0) score = 1.0;
    return score;
}

double HybridIntelligenceEngine::computeTitleBodyMatch(
    const std::string& title, const std::string& body) {
    if (title.empty() || body.empty()) return 0.0;

    std::string body_lower = body;
    std::transform(body_lower.begin(), body_lower.end(), body_lower.begin(),
                   [](unsigned char c){ return std::tolower(c); });

    int title_words = 0;
    int matched = 0;
    std::string word;
    for (char c : title) {
        if (std::isalpha((unsigned char)c)) {
            word += std::tolower((unsigned char)c);
        } else {
            if (word.length() > 3) {
                title_words++;
                if (body_lower.find(word) != std::string::npos) matched++;
            }
            word.clear();
        }
    }
    if (word.length() > 3) {
        title_words++;
        if (body_lower.find(word) != std::string::npos) matched++;
    }

    if (title_words == 0) return 0.5;
    return (double)matched / (double)title_words;
}

std::string HybridIntelligenceEngine::buildTinyLlmPrompt(
    const std::string& title,
    const std::string& body,
    const std::string& summary,
    const HybridIntelligenceResult& current) {

    std::ostringstream oss;
    oss << "Task: Determine if this is real news and classify it.\n";
    oss << "Title: " << title << "\n";
    oss << "Body: " << body.substr(0, 500) << "\n";
    oss << "Summary: " << summary << "\n";
    oss << "Current scores: news_signal=" << current.scores.news_signal_score
        << ", event_spec=" << current.scores.event_specificity_score
        << ", title_match=" << current.scores.title_body_match_score << "\n";
    oss << "Respond with JSON: {\"is_real_news\": bool, \"event_type\": string, "
        << "\"confidence\": float, \"reasoning\": string}\n";
    return oss.str();
}

std::string HybridIntelligenceEngine::invokeTinyLlm(const std::string& prompt) {
    return "{\"is_real_news\": true, \"event_type\": \"unspecified\", "
           "\"confidence\": 0.5, \"reasoning\": \"TinyLLM not integrated\"}";
}

void HybridIntelligenceEngine::parseTinyLlmResponse(
    HybridIntelligenceResult& result, const std::string& response) {

    if (response.find("\"is_real_news\": true") != std::string::npos) {
        result.semantic_confidence = 0.7;
    } else if (response.find("\"is_real_news\": false") != std::string::npos) {
        result.semantic_confidence = 0.2;
        result.validation.rejection_reasons.push_back(
            "TinyLLM classified as non-news");
    }

    size_t conf_pos = response.find("\"confidence\":");
    if (conf_pos != std::string::npos) {
        size_t start = conf_pos + 13;
        size_t end = response.find_first_of(",}", start);
        if (end != std::string::npos) {
            std::string conf_str = response.substr(start, end - start);
            try {
                result.semantic_confidence = std::stod(conf_str);
            } catch (...) {}
        }
    }

    result.scores.semantic_confidence = result.semantic_confidence;
}

} // namespace newsbrain

#ifdef __cplusplus
extern "C" {
#endif

NEWSBRAIN_HYBRID_EXPORT void* newsbrain_hybrid_create(
    int enable_tiny_llm,
    const char* model_path,
    const char* knowledge_base_path,
    size_t working_memory_bytes) {

    newsbrain::HybridIntelligenceConfig config;
    config.enable_tiny_llm = (enable_tiny_llm != 0);
    config.model_path = model_path ? model_path : "";
    config.knowledge_base_path = knowledge_base_path ? knowledge_base_path : "";
    config.working_memory_bytes = working_memory_bytes;

    auto* engine = new (std::nothrow) newsbrain::HybridIntelligenceEngine(config);
    if (!engine || !engine->isHealthy()) {
        delete engine;
        return nullptr;
    }
    return engine;
}

NEWSBRAIN_HYBRID_EXPORT void newsbrain_hybrid_destroy(void* engine) {
    delete static_cast<newbrain::HybridIntelligenceEngine*>(engine);
}

NEWSBRAIN_HYBRID_EXPORT const char* newsbrain_hybrid_process(
    void* engine,
    const char* title,
    const char* body,
    const char* summary,
    const char* url,
    const char* language,
    const char* source_id,
    const char* published_date) {

    if (!engine) return nullptr;

    auto* eng = static_cast<newbrain::HybridIntelligenceEngine*>(engine);
    auto result = eng->process(
        title ? title : "",
        body ? body : "",
        summary ? summary : "",
        url ? url : "",
        language ? language : "en",
        source_id ? source_id : "",
        published_date ? published_date : ""
    );

    std::ostringstream oss;
    oss << "{";
    oss << "\"decision\":\"" << newsbrain::decisionToString(result.decision) << "\",";
    oss << "\"overall_score\":" << result.scores.overallScore() << ",";
    oss << "\"news_signal\":" << result.scores.news_signal_score << ",";
    oss << "\"event_specificity\":" << result.scores.event_specificity_score << ",";
    oss << "\"title_body_match\":" << result.scores.title_body_match_score << ",";
    oss << "\"semantic_confidence\":" << result.scores.semantic_confidence << ",";
    oss << "\"freshness\":" << result.scores.freshness_score << ",";
    oss << "\"category_confidence\":" << result.scores.category_confidence << ",";
    oss << "\"duplicate_probability\":" << result.scores.duplicate_probability << ",";
    oss << "\"importance\":" << result.scores.importance_score << ",";
    oss << "\"extraction_confidence\":" << result.scores.extraction_confidence << ",";
    oss << "\"category\":\"" << newsbrain::categoryToString(result.category.primary) << "\",";
    oss << "\"category_conf\":" << result.category.primary_confidence << ",";
    oss << "\"event_action\":\"" << result.event.action << "\",";
    oss << "\"event_subject\":\"" << result.event.subject << "\",";
    oss << "\"event_object\":\"" << result.event.object << "\",";
    oss << "\"event_conf\":" << result.event.confidence << ",";
    oss << "\"is_new_development\":" << (result.event.is_new_development ? "true" : "false") << ",";
    oss << "\"headline_sensational\":" << (result.headline.is_sensational ? "true" : "false") << ",";
    oss << "\"headline_clickbait\":" << (result.headline.is_clickbait ? "true" : "false") << ",";
    oss << "\"title_body_mismatch\":" << (result.headline.title_body_mismatch ? "true" : "false") << ",";
    oss << "\"is_real_news\":" << (result.validation.is_real_news ? "true" : "false") << ",";
    oss << "\"has_event_evidence\":" << (result.validation.has_event_evidence ? "true" : "false") << ",";
    oss << "\"tiny_llm_calls\":" << result.tiny_llm_invoked << ",";
    oss << "\"processing_ms\":" << result.processing_time_ms << ",";
    oss << "\"explainability\":\"" << result.explainability << "\",";
    oss << "\"knowledge_version\":\"" << result.knowledge_version << "\",";
    oss << "\"rejection_reasons\":[";
    for (size_t i = 0; i < result.validation.rejection_reasons.size(); ++i) {
        if (i > 0) oss << ",";
        oss << "\"" << result.validation.rejection_reasons[i] << "\"";
    }
    oss << "],\"warnings\":[";
    for (size_t i = 0; i < result.validation.warnings.size(); ++i) {
        if (i > 0) oss << ",";
        oss << "\"" << result.validation.warnings[i] << "\"";
    }
    oss << "]}";

    const std::string& json_str = oss.str();
    char* out = new (std::nothrow) char[json_str.size() + 1];
    if (!out) return nullptr;
    std::memcpy(out, json_str.c_str(), json_str.size() + 1);
    return out;
}

NEWSBRAIN_HYBRID_EXPORT void newsbrain_hybrid_free_string(const char* str) {
    delete[] static_cast<const char*>(str);
}

NEWSBRAIN_HYBRID_EXPORT const char* newsbrain_hybrid_version() {
    return "NewsBrain Hybrid Intelligence v1.0.0";
}

NEWSBRAIN_HYBRID_EXPORT void newsbrain_hybrid_record_feedback(
    void* engine,
    const char* article_id,
    int original_decision,
    int corrected_decision,
    const char* correction_reason) {

    if (!engine) return;
    auto* eng = static_cast<newbrain::HybridIntelligenceEngine*>(engine);
    eng->recordFeedback(
        article_id ? article_id : "",
        static_cast<newsbrain::NewsDecision>(original_decision),
        static_cast<newsbrain::NewsDecision>(corrected_decision),
        correction_reason ? correction_reason : ""
    );
}

#ifdef __cplusplus
}
#endif
