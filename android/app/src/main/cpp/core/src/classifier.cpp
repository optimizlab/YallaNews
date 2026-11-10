#include "yalla_core.h"
#include <string>
#include <vector>
#include <unordered_map>
#include <algorithm>
#include <cctype>

struct YallaClassifier {
    // Category keywords mapping - expanded from arabic_nlp.cpp with French/English
    std::unordered_map<std::string, std::vector<std::string>> category_keywords = {
        {"politics", {
            // Arabic
            "سياسة", "حكومة", "رئيس", "وزير", "برلمان", "انتخابات", "دبلوماسي", "مجلس", "نواب", "وزارة",
            "قانون", "دستور", "حزب", "معارضة", "ائتلاف", "تصويت", "مرشح", "حملات", "استفتاء",
            // English
            "politics", "government", "president", "minister", "parliament", "election", "policy", "diplomatic",
            "congress", "senate", "legislation", "cabinet", "ambassador", "treaty", "summit", "vote",
            "candidate", "campaign", "referendum", "coalition", "opposition", "bill", "constitution",
            // French
            "politique", "gouvernement", "president", "ministre", "parlement", "election", "diplomatie",
            "conseil", "ministre", "depute", "senat", "loi", "constitution", "parti", "coalition",
            "vote", "candidat", "campagne", "referendum", "traite", "sommet"
        }},
        {"business", {
            // Arabic
            "اقتصاد", "سوق", "بورصة", "استثمار", "بنك", "تجارة", "مالي", "شركة", "نمو", "تضخم",
            "ميزانية", "عملة", "أسعار", "ارباح", "خسائر", "اسهم", "سندات", "تمويل", "مصرف",
            // English
            "economy", "market", "stock", "investment", "bank", "trade", "financial", "business",
            "company", "growth", "inflation", "budget", "currency", "profit", "loss", "shares",
            "bonds", "funding", "revenue", "earnings", "quarterly", "fiscal", "monetary",
            // French
            "economie", "marche", "bourse", "investissement", "banque", "commerce", "finance",
            "entreprise", "croissance", "inflation", "budget", "devise", "benefice", "perte",
            "actions", "obligations", "financement", "chiffre_affaires", "resultats"
        }},
        {"technology", {
            // Arabic
            "تكنولوجيا", "برمجيات", "ذكاء اصطناعي", "رقمي", "تقنية", "ابتكار", "هاتف", "انترنت",
            "تطبيق", "برمجة", "حاسوب", "روبوت", "بلوكشين", "عملات رقمية", "سيبر", "امن معلومات",
            // English
            "technology", "software", "ai", "artificial intelligence", "digital", "tech", "innovation",
            "phone", "internet", "app", "programming", "computer", "robot", "blockchain", "crypto",
            "cyber", "security", "startup", "platform", "algorithm", "machine learning", "cloud",
            // French
            "technologie", "logiciel", "intelligence artificielle", "numerique", "innovation",
            "telephone", "internet", "application", "programmation", "ordinateur", "robot",
            "blockchain", "crypto", "cybersecurite", "startup", "plateforme", "algorithme"
        }},
        {"sports", {
            // Arabic
            "رياضة", "كرة القدم", "مباراة", "فريق", "لاعب", "بطولة", "دوري", "هدف", "كأس",
            "ريال مدريد", "برشلونة", "الكلاسيكو", "منتخب", "مدرب", "ملعب", "حكم", "بطاقة",
            // English
            "sports", "football", "soccer", "match", "team", "player", "championship", "league", "goal",
            "cup", "real madrid", "barcelona", "el clasico", "national team", "coach", "stadium",
            "referee", "tournament", "victory", "defeat", "score", "transfer", "injury",
            // French
            "sport", "football", "match", "equipe", "joueur", "championnat", "ligue", "but",
            "coupe", "real madrid", "barcelone", "el clasico", "selection", "entraineur", "stade",
            "arbitre", "tournoi", "victoire", "defaite", "score", "transfert", "blesse"
        }},
        {"health", {
            // Arabic
            "صحة", "مستشفى", "طبيب", "مرض", "علاج", "لقاح", "طبي", "فيروس", "وباء", "وزارة الصحة",
            "مريض", "دواء", "صيدلية", "مختبر", "تحليل", "جراحة", "طوارئ", "اسعاف",
            // English
            "health", "hospital", "doctor", "disease", "treatment", "vaccine", "medical", "virus",
            "pandemic", "patient", "medicine", "pharmacy", "lab", "test", "surgery", "emergency",
            "clinic", "symptoms", "diagnosis", "therapy", "prevention", "who", "cdc",
            // French
            "sante", "hopital", "medecin", "maladie", "traitement", "vaccin", "medical", "virus",
            "pandemie", "patient", "medicament", "pharmacie", "laboratoire", "analyse", "chirurgie",
            "urgence", "clinique", "symptomes", "diagnostic", "therapie", "prevention", "oms"
        }},
        {"science", {
            // Arabic
            "علم", "بحث", "دراسة", "اكتشاف", "تجربة", "مختبر", "فضاء", "كوكب", "فيزياء", "كيمياء",
            "بيولوجيا", "ناسا", "قمر", "مريخ", "محطة فضاء", "تلسكوب", "قمر صناعي", "مدار",
            // English
            "science", "research", "study", "discovery", "experiment", "lab", "space", "planet",
            "physics", "chemistry", "biology", "nasa", "moon", "mars", "iss", "telescope",
            "satellite", "orbit", "astronomy", "quantum", "genetics", "climate", "environment",
            // French
            "science", "recherche", "etude", "decouverte", "experience", "laboratoire", "espace",
            "planete", "physique", "chimie", "biologie", "nasa", "lune", "mars", "iss",
            "telescope", "satellite", "orbite", "astronomie", "quantique", "genetique", "climat"
        }},
        {"culture", {
            // Arabic
            "ثقافة", "فن", "متحف", "معرض", "تراث", "مهرجان", "كتاب", "رواية", "شاعر", "ناقد",
            "مسرح", "سينما", "فيلم", "ممثل", "موسيقى", "حفلة", "اوبرا", "باليه", "اثار",
            // English
            "culture", "art", "museum", "exhibition", "heritage", "festival", "book", "novel",
            "poet", "critic", "theater", "cinema", "film", "actor", "music", "concert",
            "opera", "ballet", "archaeology", "literature", "painting", "sculpture", "gallery",
            // French
            "culture", "art", "musee", "exposition", "patrimoine", "festival", "livre", "roman",
            "poete", "critique", "theatre", "cinema", "film", "acteur", "musique", "concert",
            "opera", "ballet", "archeologie", "litterature", "peinture", "sculpture", "galerie"
        }},
        {"world", {
            // Arabic
            "العالم", "دولي", "عالمي", "عالم", "دولة", "أجنبي", "خارجية", "سفارة", "قمة",
            "امريكا", "اوروبا", "آسيا", "افريقيا", "شرق اوسط", "امم متحدة", "مجلس امن",
            // English
            "world", "international", "global", "country", "nation", "foreign", "diplomacy",
            "embassy", "summit", "america", "europe", "asia", "africa", "middle east",
            "un", "united nations", "security council", "treaty", "alliance", "sanctions",
            // French
            "monde", "international", "mondial", "pays", "nation", "etranger", "diplomatie",
            "ambassade", "sommet", "amerique", "europe", "asie", "afrique", "moyen orient",
            "onu", "nations unies", "conseil securite", "traite", "alliance", "sanctions"
        }},
        {"society", {
            // Arabic
            "مجتمع", "عائلة", "تعليم", "شباب", "مرأة", "طفل", "مدرسة", "جامعة", "زواج", "طلاق",
            "حماية الطفل", "حقوق الانسان", "عمل", "بطالة", "فقر", "اسكان", "نقل", "مرور",
            // English
            "society", "family", "education", "youth", "women", "children", "school", "university",
            "marriage", "divorce", "child protection", "human rights", "work", "unemployment",
            "poverty", "housing", "transport", "traffic", "crime", "justice", "law",
            // French
            "societe", "famille", "education", "jeunes", "femmes", "enfants", "ecole", "universite",
            "mariage", "divorce", "protection enfance", "droits homme", "travail", "chomage",
            "pauvrete", "logement", "transport", "trafic", "crime", "justice", "droit"
        }},
        {"entertainment", {
            // Arabic
            "ترفيه", "مشاهير", "فنان", "مغني", "ممثل", "برنامج", "تلفزيون", "يوتيوب", "تيك توك",
            "انستغرام", "سناب شات", "موضة", "جمال", "سياحة", "سفر", "مطعم", "قهوة",
            // English
            "entertainment", "celebrity", "artist", "singer", "actor", "show", "tv", "youtube",
            "tiktok", "instagram", "snapchat", "fashion", "beauty", "tourism", "travel",
            "restaurant", "food", "lifestyle", "viral", "trending", "influencer",
            // French
            "divertissement", "celébrité", "artiste", "chanteur", "acteur", "emission", "tv",
            "youtube", "tiktok", "instagram", "snapchat", "mode", "beaute", "tourisme", "voyage",
            "restaurant", "cuisine", "style de vie", "viral", "tendance", "influenceur"
        }}
    };

    std::string classify_text(const std::string& text, float* confidence) {
        std::string lower = text;
        std::transform(lower.begin(), lower.end(), lower.begin(),
            [](unsigned char c) { return std::tolower(c); });

        std::string best_category = "general";
        int best_score = 0;
        int total_score = 0;

        for (const auto& [cat, keywords] : category_keywords) {
            int score = 0;
            for (const auto& kw : keywords) {
                std::string lower_kw = kw;
                std::transform(lower_kw.begin(), lower_kw.end(), lower_kw.begin(),
                    [](unsigned char c) { return std::tolower(c); });
                if (lower.find(lower_kw) != std::string::npos) score++;
            }
            total_score += score;
            if (score > best_score) {
                best_score = score;
                best_category = cat;
            }
        }

        if (confidence) {
            if (best_score > 0 && total_score > 0) {
                *confidence = std::min(0.5f + (static_cast<float>(best_score) / total_score) * 0.4f, 0.95f);
            } else {
                *confidence = 0.3f;
            }
        }
        return best_category;
    }
};

extern "C" {

YALLA_CORE_EXPORT YallaClassifierHandle yalla_classifier_create() {
    return new YallaClassifier();
}

YALLA_CORE_EXPORT void yalla_classifier_destroy(YallaClassifierHandle handle) {
    if (handle) delete static_cast<YallaClassifier*>(handle);
}

YALLA_CORE_EXPORT const char* yalla_classifier_classify(YallaClassifierHandle handle,
    const char* title, const char* content, const char* summary, float* confidence) {
    if (!handle) return strdup("general");
    auto* classifier = static_cast<YallaClassifier*>(handle);

    std::string combined;
    if (title) combined += title;
    combined += " ";
    if (content) combined += content;
    combined += " ";
    if (summary) combined += summary;

    float conf = 0;
    std::string category = classifier->classify_text(combined, &conf);
    if (confidence) *confidence = conf;

    return strdup(category.c_str());
}

YALLA_CORE_EXPORT const char* yalla_classifier_get_subcategory(YallaClassifierHandle handle,
    const char* title, const char* content, const char* summary) {
    if (!handle) return strdup("");
    auto* classifier = static_cast<YallaClassifier*>(handle);

    std::string combined;
    if (title) combined += title;
    combined += " ";
    if (content) combined += content;
    combined += " ";
    if (summary) combined += summary;

    // For sports, detect subcategory (football, basketball, tennis, etc.)
    std::string lower = combined;
    std::transform(lower.begin(), lower.end(), lower.begin(),
        [](unsigned char c) { return std::tolower(c); });

    // Sports subcategories (multilingual)
    if (lower.find("football") != std::string::npos || lower.find("soccer") != std::string::npos ||
        lower.find("كرة القدم") != std::string::npos || lower.find("foot") != std::string::npos)
        return strdup("football");
    if (lower.find("basketball") != std::string::npos || lower.find("كرة السلة") != std::string::npos ||
        lower.find("basket") != std::string::npos)
        return strdup("basketball");
    if (lower.find("tennis") != std::string::npos || lower.find("تنس") != std::string::npos)
        return strdup("tennis");
    if (lower.find("cricket") != std::string::npos || lower.find("كريكيت") != std::string::npos)
        return strdup("cricket");
    if (lower.find("volleyball") != std::string::npos || lower.find("كرة الطائرة") != std::string::npos)
        return strdup("volleyball");
    if (lower.find("handball") != std::string::npos || lower.find("كرة اليد") != std::string::npos)
        return strdup("handball");
    if (lower.find("swimming") != std::string::npos || lower.find("سباحة") != std::string::npos ||
        lower.find("natation") != std::string::npos)
        return strdup("swimming");
    if (lower.find("athletics") != std::string::npos || lower.find("ألعاب قوى") != std::string::npos ||
        lower.find("athletisme") != std::string::npos)
        return strdup("athletics");

    // Tech subcategories
    if (lower.find("ai") != std::string::npos || lower.find("artificial intelligence") != std::string::npos ||
        lower.find("ذكاء اصطناعي") != std::string::npos || lower.find("intelligence artificielle") != std::string::npos)
        return strdup("ai");
    if (lower.find("crypto") != std::string::npos || lower.find("bitcoin") != std::string::npos ||
        lower.find("blockchain") != std::string::npos || lower.find("عملات رقمية") != std::string::npos ||
        lower.find("crypto-monnaie") != std::string::npos)
        return strdup("crypto");
    if (lower.find("mobile") != std::string::npos || lower.find("phone") != std::string::npos ||
        lower.find("هاتف") != std::string::npos || lower.find("smartphone") != std::string::npos ||
        lower.find("téléphone") != std::string::npos)
        return strdup("mobile");
    if (lower.find("cyber") != std::string::npos || lower.find("security") != std::string::npos ||
        lower.find("امن معلومات") != std::string::npos || lower.find("cybersécurité") != std::string::npos)
        return strdup("cybersecurity");
    if (lower.find("cloud") != std::string::npos || lower.find("سحابة") != std::string::npos ||
        lower.find("informatique en nuage") != std::string::npos)
        return strdup("cloud");
    if (lower.find("quantum") != std::string::npos || lower.find("كمومي") != std::string::npos ||
        lower.find("quantique") != std::string::npos)
        return strdup("quantum");

    // Business subcategories
    if (lower.find("stock") != std::string::npos || lower.find("bourse") != std::string::npos ||
        lower.find("سوق الأسهم") != std::string::npos || lower.find("marché boursier") != std::string::npos)
        return strdup("stocks");
    if (lower.find("bank") != std::string::npos || lower.find("بنك") != std::string::npos ||
        lower.find("banque") != std::string::npos)
        return strdup("banking");
    if (lower.find("startup") != std::string::npos || lower.find("شركة ناشئة") != std::string::npos)
        return strdup("startups");

    // Health subcategories
    if (lower.find("covid") != std::string::npos || lower.find("كورونا") != std::string::npos)
        return strdup("pandemic");
    if (lower.find("cancer") != std::string::npos || lower.find("سرطان") != std::string::npos ||
        lower.find("cancer") != std::string::npos)
        return strdup("oncology");
    if (lower.find("mental") != std::string::npos || lower.find("نفسي") != std::string::npos ||
        lower.find("santé mentale") != std::string::npos)
        return strdup("mental_health");

    return strdup("");
}

} // extern "C"