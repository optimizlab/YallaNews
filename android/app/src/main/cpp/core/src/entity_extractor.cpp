#include "yalla_core.h"
#include <string>
#include <vector>
#include <regex>
#include <unordered_map>
#include <algorithm>
#include <cctype>
#include <set>
#include <map>

struct YallaEntityExtractor {
    // Person patterns (multilingual)
    std::vector<std::pair<std::string, std::string>> person_patterns = {
        {"person", R"(\b(?:Mr\.|Mrs\.|Ms\.|Dr\.|Prof\.)\s+[A-Z][a-z]+(?:\s+[A-Z][a-z]+)*\b)"},
        {"person", R"(\b[A-Z][a-z]+\s+[A-Z][a-z]+\b)"},
        // Arabic person patterns
        {"person", R"(?:(?:السيد|السيدة|الدكتور|البروفيسور|الأستاذ|الوزير|الرئيس|الملك|الأمير|الشيخ)\s+[\u0600-\u06FF]+(?:\s+[\u0600-\u06FF]+)*)"},
        {"person", R"([\u0600-\u06FF]+\s+[\u0600-\u06FF]+\s+(?:بن|بنت|ابو|ام|ال)\s+[\u0600-\u06FF]+)"},
        // French person patterns
        {"person", R"(\b(?:M\.|Mme\.|Mlle\.|Dr\.|Pr\.)\s+[A-ZÀ-ÿ][a-zà-ÿ]+(?:\s+[A-ZÀ-ÿ][a-zà-ÿ]+)*\b)"},
        {"person", R"(\b[A-ZÀ-ÿ][a-zà-ÿ]+\s+[A-ZÀ-ÿ][a-zà-ÿ]+\b)"}
    };

    // Organization patterns
    std::vector<std::pair<std::string, std::string>> org_patterns = {
        {"organization", R"(\b(?:Inc\.|Corp\.|LLC|Ltd\.|Company|Corporation|Group|Organization|Foundation|Institute|University|Association)\b)"},
        {"organization", R"(\b[A-Z][a-z]+(?:\s+[A-Z][a-z]+)*\s+(?:Inc|Corp|LLC|Ltd|Group|Org|Foundation|Institute|University|Association)\b)"},
        // Arabic org patterns
        {"organization", R"((?:شركة|مؤسسة|بنك|جامعة|وزارة|هيئة|منظمة|جمعية|مركز|مجموعة|قوة|جيش|شرطة|حكومة)\s+[\u0600-\u06FF]+)"},
        // French org patterns
        {"organization", R"(\b(?:SA|SARL|SAS|Groupe|Fondation|Institut|Université|Association|Ministère|Banque|Société)\b)"}
    };

    // Location patterns
    std::vector<std::pair<std::string, std::string>> location_patterns = {
        {"location", R"(\b(?:in|at|from|to|near|around)\s+[A-Z][a-z]+(?:\s+[A-Z][a-z]+)*\b)"},
        {"location", R"(\b[A-Z][a-z]+(?:\s+[A-Z][a-z]+)*,\s*[A-Z]{2}\b)"}, // City, State
        // Arabic locations
        {"location", R"(?:(?:في|ب|من|إلى|على|بجانب|قرب|حول)\s+[\u0600-\u06FF]+(?:\s+[\u0600-\u06FF]+)*)"},
        {"location", R"([\u0600-\u06FF]+(?:\s+[\u0600-\u06FF]+)*\s+(?:محافظة|مدينة|قرية|حي|شارع|ميدان|جامعة|مطار|مستشفى|مدرسة))"},
        // French locations
        {"location", R"(\b(?:à|dans|de|vers|près de|autour de)\s+[A-ZÀ-ÿ][a-zà-ÿ]+(?:\s+[A-ZÀ-ÿ][a-zà-ÿ]+)*\b)"},
        {"location", R"(\b[A-ZÀ-ÿ][a-zà-ÿ]+(?:\s+[A-ZÀ-ÿ][a-zà-ÿ]+)*,\s*[A-ZÀ-ÿ]{2,}\b)"}
    };

    // Date patterns
    std::vector<std::pair<std::string, std::string>> date_patterns = {
        {"date", R"(\b\d{1,2}[-/]\d{1,2}[-/]\d{2,4}\b)"},
        {"date", R"(\b\d{4}[-/]\d{1,2}[-/]\d{1,2}\b)"},
        {"date", R"(\b(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+\d{1,2},?\s+\d{4}\b)"},
        {"date", R"(\b(?:January|February|March|April|May|June|July|August|September|October|November|December)\s+\d{1,2},?\s+\d{4}\b)"},
        // Arabic dates
        {"date", R"(\b\d{1,2}\s+(?:يناير|فبراير|مارس|أبريل|مايو|يونيو|يوليو|أغسطس|سبتمبر|أكتوبر|نوفمبر|ديسمبر)\s+\d{4}\b)"},
        {"date", R"(\b(?:أمس|اليوم|غداً|غدا|قبل\s+\d+\s+يوم|بعد\s+\d+\s+يوم)\b)"},
        // French dates
        {"date", R"(\b\d{1,2}\s+(?:janvier|février|mars|avril|mai|juin|juillet|août|septembre|octobre|novembre|décembre)\s+\d{4}\b)"},
        {"date", R"(\b(?:hier|aujourd'hui|demain|avant-hier|après-demain)\b)"}
    };

    // Money/Currency patterns
    std::vector<std::pair<std::string, std::string>> money_patterns = {
        {"money", R"(\$\s*\d+(?:,\d{3})*(?:\.\d{2})?)"},
        {"money", R"(\b\d+(?:,\d{3})*(?:\.\d{2})?\s*(?:USD|EUR|GBP|SAR|AED|EGP|MAD|TND|JOD|KWD|BHD|OMR|QAR)\b)"},
        {"money", R"(\b(?:مليون|مليار|ألف)\s*(?:دولار|يورو|جنيه|ريال|درهم|دينار)\b)"}
    };

    // Sports team patterns
    std::vector<std::pair<std::string, std::string>> sports_team_patterns = {
        {"sports_team", R"(\b(?:Real Madrid|Barcelona|Manchester United|Liverpool|Bayern Munich|PSG|Juventus|Inter Milan|AC Milan|Atletico Madrid|Chelsea|Arsenal|Tottenham|Dortmund|RB Leipzig|Napoli|Lazio|Roma|Sevilla|Valencia|Villarreal|Real Sociedad|Athletic Bilbao|Real Betis|Osasuna|Celta Vigo|Getafe|Elche|Cadiz|Almeria|Granada|Mallorca|Rayo Vallecano|Barcelona)\b)"},
        {"sports_team", R"(\b(?:ريال مدريد|برشلونة|أتلتيكو مدريد|إشبيلية|فالنسيا|فياريال|ريال سوسيداد|أتلتيك بيلباو|ريال بيتيس|أوساسونا|سيلتا فيغو|خيتافي|إلتشي|قادش|الميريا|غرناطة|مايوركا|رايوفايكانو)\b)"},
        {"sports_team", R"(\b(?:Manchester City|Manchester United|Liverpool|Chelsea|Arsenal|Tottenham|Newcastle|Aston Villa|Brighton|Brentford|Crystal Palace|Fulham|Everton|Leicester|Leeds|Southampton|Wolves|West Ham|Nottingham Forest|Bournemouth)\b)"}
    };

    // Canonical name mappings for cross-language entity preservation
    std::unordered_map<std::string, std::string> canonical_names = {
        // People
        {"joe biden", "Joe Biden"}, {"biden", "Joe Biden"},
        {"emmanuel macron", "Emmanuel Macron"}, {"macron", "Emmanuel Macron"},
        {"vladimir putin", "Vladimir Putin"}, {"putin", "Vladimir Putin"},
        {"xi jinping", "Xi Jinping"}, {"xi", "Xi Jinping"},
        {"narendra modi", "Narendra Modi"}, {"modi", "Narendra Modi"},
        {"rizk", "Rizk"}, {"رياض رزق", "Riyad Rizk"},
        // Organizations
        {"un", "United Nations"}, {"united nations", "United Nations"},
        {"الأمم المتحدة", "United Nations"}, {"nations unies", "United Nations"},
        {"eu", "European Union"}, {"european union", "European Union"},
        {"الاتحاد الأوروبي", "European Union"}, {"union européenne", "European Union"},
        {"nato", "NATO"}, {"حلف الناتو", "NATO"}, {"otan", "NATO"},
        {"who", "WHO"}, {"منظمة الصحة العالمية", "WHO"}, {"oms", "WHO"},
        {"fifa", "FIFA"}, {"فيفا", "FIFA"},
        {"google", "Google"}, {"مايكروسوفت", "Microsoft"}, {"microsoft", "Microsoft"},
        {"apple", "Apple"}, {"أبل", "Apple"},
        {"amazon", "Amazon"}, {"أمازون", "Amazon"},
        {"meta", "Meta"}, {"فيسبوك", "Facebook"}, {"facebook", "Facebook"},
        // Locations
        {"usa", "United States"}, {"united states", "United States"},
        {"الولايات المتحدة", "United States"}, {"états-unis", "United States"},
        {"uk", "United Kingdom"}, {"united kingdom", "United Kingdom"},
        {"المملكة المتحدة", "United Kingdom"}, {"royaume-uni", "United Kingdom"},
        {"china", "China"}, {"الصين", "China"}, {"chine", "China"},
        {"russia", "Russia"}, {"روسيا", "Russia"}, {"russie", "Russia"},
        {"france", "France"}, {"فرنسا", "France"},
        {"germany", "Germany"}, {"ألمانيا", "Germany"}, {"allemagne", "Germany"},
        {"saudi arabia", "Saudi Arabia"}, {"السعودية", "Saudi Arabia"}, {"arabie saoudite", "Saudi Arabia"},
        {"egypt", "Egypt"}, {"مصر", "Egypt"}, {"égypte", "Egypt"},
        {"uae", "UAE"}, {"الإمارات", "UAE"}, {"émirats", "UAE"},
        // Sports teams (canonical English names)
        {"real madrid", "Real Madrid"}, {"ريال مدريد", "Real Madrid"},
        {"barcelona", "Barcelona"}, {"برشلونة", "Barcelona"},
        {"manchester united", "Manchester United"}, {"مانشستر يونايتد", "Manchester United"},
        {"liverpool", "Liverpool"}, {"ليفربول", "Liverpool"},
        {"psg", "Paris Saint-Germain"}, {"باريس سان جيرمان", "Paris Saint-Germain"},
        // Currency
        {"usd", "USD"}, {"دولار", "USD"}, {"dollar", "USD"},
        {"eur", "EUR"}, {"يورو", "EUR"}, {"euro", "EUR"},
        {"sar", "SAR"}, {"ريال", "SAR"}, {"riyal", "SAR"},
        {"aed", "AED"}, {"درهم", "AED"}, {"dirham", "AED"},
    };

    std::string get_canonical(const std::string& value, const std::string& language) const {
        std::string lower = value;
        std::transform(lower.begin(), lower.end(), lower.begin(),
            [](unsigned char c) { return std::tolower(c); });

        // Direct lookup
        auto it = canonical_names.find(lower);
        if (it != canonical_names.end()) return it->second;

        // Fuzzy match for partial matches
        for (const auto& [key, canonical] : canonical_names) {
            if (lower.find(key) != std::string::npos || key.find(lower) != std::string::npos) {
                return canonical;
            }
        }

        // Return original with proper casing
        return value;
    }

    // Extract entities with language-specific patterns
    std::vector<YallaEntity> extract_entities(const std::string& text, const std::string& language) {
        std::vector<YallaEntity> entities;
        std::set<std::string> seen_values; // For deduplication

        auto add_entities_from_patterns = [&](const std::vector<std::pair<std::string, std::string>>& patterns) {
            for (const auto& [type, pattern] : patterns) {
                try {
                    std::regex re(pattern, std::regex_constants::icase);
                    auto words_begin = std::sregex_iterator(text.begin(), text.end(), re);
                    auto words_end = std::sregex_iterator();

                    for (std::sregex_iterator i = words_begin; i != words_end; ++i) {
                        std::smatch match = *i;
                        std::string value = match.str();
                        // Trim whitespace
                        value.erase(0, value.find_first_not_of(" \t\n\r"));
                        value.erase(value.find_last_not_of(" \t\n\r") + 1);

                        if (value.empty() || value.length() < 2) continue;
                        if (seen_values.count(value)) continue;
                        seen_values.insert(value);

                        YallaEntity entity;
                        entity.type = strdup(type.c_str());
                        entity.value = strdup(value.c_str());
                        entity.canonical = strdup(get_canonical(value, language).c_str());
                        entity.language = strdup(language.c_str());
                        entity.confidence = 0.7;
                        entities.push_back(entity);
                    }
                } catch (const std::regex_error&) {
                    // Invalid regex, skip
                }
            }
        };

        // Common patterns for all languages
        add_entities_from_patterns(person_patterns);
        add_entities_from_patterns(org_patterns);
        add_entities_from_patterns(location_patterns);
        add_entities_from_patterns(date_patterns);
        add_entities_from_patterns(money_patterns);
        add_entities_from_patterns(sports_team_patterns);

        // Language-specific patterns
        if (language == "ar" || language == "arabic") {
            // Arabic-specific patterns (already included in common patterns above)
        } else if (language == "fr" || language == "french") {
            // French-specific patterns (already included)
        } else if (language == "en" || language == "english") {
            // English-specific patterns (already included)
        }

        // Sort by confidence (could be enhanced with position-based scoring)
        return entities;
    }
};

extern "C" {

YALLA_CORE_EXPORT YallaEntityExtractorHandle yalla_entity_extractor_create() {
    return new YallaEntityExtractor();
}

YALLA_CORE_EXPORT void yalla_entity_extractor_destroy(YallaEntityExtractorHandle handle) {
    if (handle) delete static_cast<YallaEntityExtractor*>(handle);
}

YALLA_CORE_EXPORT YallaEntity* yalla_entity_extractor_extract(YallaEntityExtractorHandle handle,
    const char* title, const char* content, const char* language, int32_t* count) {
    if (!handle || !count) return nullptr;
    auto* extractor = static_cast<YallaEntityExtractor*>(handle);

    std::string combined;
    if (title) combined += title;
    combined += " ";
    if (content) combined += content;
    std::string lang = language ? language : "en";

    std::vector<YallaEntity> entities = extractor->extract_entities(combined, lang);

    *count = static_cast<int32_t>(entities.size());
    if (entities.empty()) return nullptr;

    YallaEntity* result = new YallaEntity[entities.size()];
    for (size_t i = 0; i < entities.size(); ++i) {
        result[i] = entities[i];
    }
    return result;
}

YALLA_CORE_EXPORT void yalla_entity_extractor_free_entities(YallaEntity* entities, int32_t count) {
    if (!entities) return;
    for (int i = 0; i < count; ++i) {
        free(const_cast<char*>(entities[i].type));
        free(const_cast<char*>(entities[i].value));
        free(const_cast<char*>(entities[i].canonical));
        free(const_cast<char*>(entities[i].language));
    }
    delete[] entities;
}

} // extern "C"