#ifndef YALLA_ARABIC_NLP_H
#define YALLA_ARABIC_NLP_H

#include <string>
#include <vector>
#include <map>

// Data structures for NLP outputs
struct NerEntity {
    std::string type;
    std::string value;
    std::string canonical;
    double confidence;
};

struct ExtractedDate {
    std::string raw;
    std::string iso;
    double confidence;
};

struct SportsMatchData {
    std::string home_team;
    std::string away_team;
    std::string match_score;
    std::string match_result;
    std::string sport_type;
    std::vector<std::string> goal_scorers;
    std::vector<std::string> injured_players;
    std::vector<std::string> cards;
    std::vector<std::string> transfers;
    std::vector<std::string> standings;
    std::string venue;
};

struct AnalysisResult {
    std::string category;
    std::string subcategory;
    double sentiment;
    double confidence;
    std::string event_type;
    std::string geo_region;
    std::vector<NerEntity> entities;
    std::vector<ExtractedDate> dates;
    SportsMatchData sports_data;
    std::vector<std::string> keywords;
    std::vector<std::string> semantic_tags;
    std::string summary;
};

// Core NLP Functions
std::string normalize_arabic(const std::string& text);
std::vector<NerEntity> extract_entities(const std::string& text);
std::vector<ExtractedDate> extract_dates(const std::string& text);
SportsMatchData extract_sports(const std::string& title, const std::string& content);
std::vector<std::string> extract_keywords(const std::string& title, const std::string& content, const std::string& summary, std::vector<std::string>& semantic_tags, const std::vector<NerEntity>& entities);
double analyze_sentiment(const std::string& text);
std::string classify_category(const std::string& title, const std::string& content, const std::string& summary, double& out_confidence);
std::string detect_event_type(const std::string& text);
std::string get_geo_region(const std::vector<NerEntity>& entities);

// Main Pipeline
AnalysisResult analyze_article_nlp(const std::string& title, const std::string& content, const std::string& summary);

#endif // YALLA_ARABIC_NLP_H
