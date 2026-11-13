#include "yalla_core.h"
#include <string>
#include <vector>
#include <unordered_map>
#include <mutex>
#include <chrono>
#include <thread>
#include <regex>
#include <nlohmann/json.hpp>
#include <sstream>
#include <iomanip>

using json = nlohmann::json;

// ============================================================================
// Base Provider Infrastructure
// ============================================================================

struct RateLimiter {
    int32_t requests_per_minute = 60;
    std::chrono::steady_clock::time_point last_request;
    std::mutex mutex;

    void wait_if_needed() {
        std::lock_guard<std::mutex> lock(mutex);
        auto now = std::chrono::steady_clock::now();
        auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(now - last_request).count();
        int64_t min_interval = 60000 / std::max(1, requests_per_minute);
        if (elapsed < min_interval) {
            std::this_thread::sleep_for(std::chrono::milliseconds(min_interval - elapsed));
        }
        last_request = std::chrono::steady_clock::now();
    }
};

struct HttpClient {
    int32_t timeout_ms = 30000;
    int32_t max_retries = 3;
    std::string user_agent = "YallaNews/1.0";

    static size_t write_callback(void* contents, size_t size, size_t nmemb, std::string* response) {
        size_t total = size * nmemb;
        response->append(static_cast<char*>(contents), total);
        return total;
    }

    static size_t header_callback(void* contents, size_t size, size_t nmemb, std::string* headers) {
        size_t total = size * nmemb;
        headers->append(static_cast<char*>(contents), total);
        return total;
    }

    std::string get(const std::string& url, const std::unordered_map<std::string, std::string>& headers = {}) {
        (void)url; (void)headers;
        return "";
    }

    std::string post(const std::string& url, const std::string& body,
                     const std::unordered_map<std::string, std::string>& headers = {}) {
        (void)url; (void)body; (void)headers;
        return "";
    }
};

// Simple in-memory cache
struct ResponseCache {
    struct CacheEntry {
        std::string data;
        std::chrono::steady_clock::time_point expires;
    };

    std::unordered_map<std::string, CacheEntry> cache;
    std::mutex mutex;
    int32_t default_ttl_seconds = 300; // 5 minutes

    std::string get(const std::string& key) {
        std::lock_guard<std::mutex> lock(mutex);
        auto it = cache.find(key);
        if (it != cache.end() && it->second.expires > std::chrono::steady_clock::now()) {
            return it->second.data;
        }
        if (it != cache.end()) cache.erase(it);
        return "";
    }

    void set(const std::string& key, const std::string& data, int32_t ttl_seconds = -1) {
        std::lock_guard<std::mutex> lock(mutex);
        int32_t ttl = ttl_seconds > 0 ? ttl_seconds : default_ttl_seconds;
        cache[key] = {data, std::chrono::steady_clock::now() + std::chrono::seconds(ttl)};
    }

    std::string make_key(const std::string& base, const std::string& params) {
        // Simple hash for cache key (no openssl dependency)
        std::string combined = base + "|" + params;
        size_t hash = std::hash<std::string>{}(combined);
        std::ostringstream oss;
        oss << std::hex << hash;
        return oss.str();
    }
};

// ============================================================================
// Provider Adapter Base
// ============================================================================

struct YallaProviderAdapter {
    YallaProviderConfig config;
    HttpClient http;
    RateLimiter rate_limiter;
    ResponseCache cache;

    YallaProviderAdapter(const YallaProviderConfig& cfg) : config(cfg) {
        http.timeout_ms = config.timeout_ms > 0 ? config.timeout_ms : 30000;
        http.max_retries = config.max_retries > 0 ? config.max_retries : 3;
        rate_limiter.requests_per_minute = config.rate_limit_rpm > 0 ? config.rate_limit_rpm : 60;
    }

    virtual ~YallaProviderAdapter() = default;

    virtual std::vector<YallaProviderArticle> fetch_articles(const std::string& query, int32_t max_results) = 0;
    virtual std::vector<YallaProviderArticle> fetch_latest(int32_t max_results) = 0;

    std::string build_cache_key(const std::string& method, const std::string& params) {
        return cache.make_key(config.provider_id ? config.provider_id : "unknown", method + "|" + params);
    }

    YallaProviderArticle create_article(const json& item, const std::string& provider_name) {
        YallaProviderArticle article{};
        // These will be strdup'd by the C API wrapper
        // For now, we store in the struct and the C++ wrapper will handle allocation
        return article;
    }
};

// ============================================================================
// RSS/Atom Provider
// ============================================================================

struct RssProvider : YallaProviderAdapter {
    std::vector<std::string> feed_urls;

    RssProvider(const YallaProviderConfig& cfg) : YallaProviderAdapter(cfg) {
        // Parse feed URLs from custom_params or use defaults
        if (config.custom_params) {
            try {
                auto params = json::parse(config.custom_params);
                if (params.contains("feeds") && params["feeds"].is_array()) {
                    for (const auto& feed : params["feeds"]) {
                        feed_urls.push_back(feed.get<std::string>());
                    }
                }
            } catch (...) {}
        }
        if (feed_urls.empty()) {
            // Default news feeds
            feed_urls = {
                "https://feeds.bbci.co.uk/news/rss.xml",
                "https://rss.nytimes.com/services/xml/rss/nyt/HomePage.xml",
                "https://www.aljazeera.com/xml/rss/all.xml",
                "https://www.lemonde.fr/rss/une.xml",
                "https://www.reuters.com/rssFeed/topNews",
                "https://feeds.skynews.com/feeds/rss/home.xml"
            };
        }
    }

    std::vector<YallaProviderArticle> fetch_articles(const std::string& query, int32_t max_results) override {
        std::vector<YallaProviderArticle> articles;
        // For RSS, query is ignored - we fetch from all feeds
        return fetch_latest(max_results);
    }

    std::vector<YallaProviderArticle> fetch_latest(int32_t max_results) override {
        std::vector<YallaProviderArticle> articles;
        int per_feed = std::max(1, max_results / static_cast<int>(feed_urls.size()));

        for (const auto& feed_url : feed_urls) {
            if (articles.size() >= static_cast<size_t>(max_results)) break;

            std::string cache_key = build_cache_key("rss_latest", feed_url);
            std::string cached = cache.get(cache_key);

            std::string xml;
            if (!cached.empty()) {
                xml = cached;
            } else {
                rate_limiter.wait_if_needed();
                xml = http.get(feed_url);
                if (!xml.empty()) {
                    cache.set(cache_key, xml, 300); // 5 min cache
                }
            }

            if (xml.empty()) continue;

            auto feed_articles = parse_rss_feed(xml, feed_url, per_feed);
            articles.insert(articles.end(), feed_articles.begin(), feed_articles.end());
        }

        return articles;
    }

private:
    std::vector<YallaProviderArticle> parse_rss_feed(const std::string& xml, const std::string& feed_url, int max_items) {
        std::vector<YallaProviderArticle> articles;

        // Simple regex-based RSS/Atom parsing
        std::regex item_regex("<item>.*?</item>", std::regex::icase | std::regex::optimize);
        std::regex title_regex("<title[^>]*><!\\[CDATA\\[(.*?)\\]\\]></title>|<title[^>]*>(.*?)</title>", std::regex::icase);
        std::regex link_regex("<link[^>]*><!\\[CDATA\\[(.*?)\\]\\]></link>|<link[^>]*>(.*?)</link>", std::regex::icase);
        std::regex desc_regex("<description[^>]*><!\\[CDATA\\[(.*?)\\]\\]></description>|<description[^>]*>(.*?)</description>", std::regex::icase);
        std::regex pubdate_regex("<pubDate[^>]*><!\\[CDATA\\[(.*?)\\]\\]></pubDate>|<pubDate[^>]*>(.*?)</pubDate>", std::regex::icase);
        std::regex guid_regex("<guid[^>]*><!\\[CDATA\\[(.*?)\\]\\]></guid>|<guid[^>]*>(.*?)</guid>", std::regex::icase);
        std::regex enclosure_regex("<enclosure[^>]+url=[\"']([^\"']+)[\"']", std::regex::icase);

        auto items_begin = std::sregex_iterator(xml.begin(), xml.end(), item_regex);
        auto items_end = std::sregex_iterator();
        int count = 0;

        for (auto i = items_begin; i != items_end && count < max_items; ++i) {
            std::string item = i->str();

            std::string title, link, description, pub_date, guid, image_url;
            extract_match(item, title_regex, title);
            extract_match(item, link_regex, link);
            extract_match(item, desc_regex, description);
            extract_match(item, pubdate_regex, pub_date);
            extract_match(item, guid_regex, guid);
            extract_match(item, enclosure_regex, image_url);

            if (title.empty() || link.empty()) continue;

            YallaProviderArticle article{};
            article.url = strdup(link.c_str());
            article.title = strdup(title.c_str());
            article.summary = strdup(description.empty() ? "" : description.c_str());
            article.content = strdup("");
            article.image_url = strdup(image_url.empty() ? "" : image_url.c_str());
            article.category = strdup("general");
            article.sentiment = 0.0;
            article.keywords = strdup("");
            article.language = strdup("en");
            article.publish_date = parse_date_to_ms(pub_date);
            article.author = strdup("");
            article.source_url = strdup(feed_url.c_str());
            article.provider_id = strdup(config.provider_id ? config.provider_id : "rss");
            article.provider_name = strdup("RSS Feed");
            article.license = strdup("CC BY-SA 4.0");
            article.attribution_url = strdup(feed_url.c_str());
            article.raw_provider_data = strdup(("{\"feed_url\":\"" + feed_url + "\",\"guid\":\"" + guid + "\"}").c_str());

            articles.push_back(article);
            count++;
        }

        return articles;
    }

    void extract_match(const std::string& text, const std::regex& re, std::string& out) {
        std::smatch match;
        if (std::regex_search(text, match, re)) {
            // Group 1 is CDATA content, group 2 is regular content
            out = match[1].matched ? match[1].str() : match[2].str();
            // Clean HTML tags
            out = std::regex_replace(out, std::regex("<[^>]+>"), "");
            out = std::regex_replace(out, std::regex("&[a-z]+;"), "");
        }
    }

    int64_t parse_date_to_ms(const std::string& date_str) {
        // Simplified date parsing - returns current time if parsing fails
        // In production, use a proper date parser like Howard Hinnant's date library
        return std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::system_clock::now().time_since_epoch()).count();
    }
};

// ============================================================================
// GDELT Provider
// ============================================================================

struct GdeltProvider : YallaProviderAdapter {
    std::string base_url = "https://api.gdeltproject.org/api/v2/doc/doc";

    GdeltProvider(const YallaProviderConfig& cfg) : YallaProviderAdapter(cfg) {
        if (config.base_url) base_url = config.base_url;
    }

    std::vector<YallaProviderArticle> fetch_articles(const std::string& query, int32_t max_results) override {
        std::vector<YallaProviderArticle> articles;

        std::string cache_key = build_cache_key("gdelt_search", query + "|" + std::to_string(max_results));
        std::string cached = cache.get(cache_key);

        std::string response;
        if (!cached.empty()) {
            response = cached;
        } else {
            rate_limiter.wait_if_needed();
            std::string url = base_url + "?query=" + curl_escape(query) +
                             "&mode=artlist&maxrecords=" + std::to_string(max_results) +
                             "&format=json";
            response = http.get(url);
            if (!response.empty()) {
                cache.set(cache_key, response, 3600); // 1 hour cache
            }
        }

        if (response.empty()) return articles;

        return parse_gdelt_response(response, max_results);
    }

    std::vector<YallaProviderArticle> fetch_latest(int32_t max_results) override {
        return fetch_articles("", max_results);
    }

private:
    std::vector<YallaProviderArticle> parse_gdelt_response(const std::string& json_str, int max_results) {
        std::vector<YallaProviderArticle> articles;
        try {
            auto data = json::parse(json_str);
            if (!data.contains("articles") || !data["articles"].is_array()) return articles;

            int count = 0;
            for (const auto& item : data["articles"]) {
                if (count >= max_results) break;

                std::string url = item.value("url", "");
                std::string title = item.value("title", "");
                if (url.empty() || title.empty()) continue;

                YallaProviderArticle article{};
                article.url = strdup(url.c_str());
                article.title = strdup(title.c_str());
                article.summary = strdup(item.value("seoTitle", "").c_str());
                article.content = strdup("");
                article.image_url = strdup(item.value("image", "").c_str());
                article.category = strdup(item.value("theme", "world").c_str());
                article.sentiment = item.value("tone", 0.0);
                article.keywords = strdup(item.value("keywords", "").c_str());
                article.language = strdup(item.value("lang", "en").c_str());
                article.publish_date = parse_gdelt_date(item.value("seendate", ""));
                article.author = strdup(item.value("source", "").c_str());
                article.source_url = strdup("https://gdeltproject.org");
                article.provider_id = strdup(config.provider_id ? config.provider_id : "gdelt");
                article.provider_name = strdup("GDELT");
                article.license = strdup("GDELT Terms of Use");
                article.attribution_url = strdup("https://gdeltproject.org");
                article.raw_provider_data = strdup(item.dump().c_str());

                articles.push_back(article);
                count++;
            }
        } catch (...) {}
        return articles;
    }

    int64_t parse_gdelt_date(const std::string& date_str) {
        // GDELT date format: YYYYMMDDHHMMSS
        if (date_str.length() >= 14) {
            try {
                int year = std::stoi(date_str.substr(0, 4));
                int month = std::stoi(date_str.substr(4, 2));
                int day = std::stoi(date_str.substr(6, 2));
                int hour = std::stoi(date_str.substr(8, 2));
                int min = std::stoi(date_str.substr(10, 2));
                int sec = std::stoi(date_str.substr(12, 2));

                std::tm tm = {};
                tm.tm_year = year - 1900;
                tm.tm_mon = month - 1;
                tm.tm_mday = day;
                tm.tm_hour = hour;
                tm.tm_min = min;
                tm.tm_sec = sec;

                auto tp = std::chrono::system_clock::from_time_t(std::mktime(&tm));
                return std::chrono::duration_cast<std::chrono::milliseconds>(tp.time_since_epoch()).count();
            } catch (...) {}
        }
        return std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::system_clock::now().time_since_epoch()).count();
    }

    std::string curl_escape(const std::string& str) {
        // Simple URL encoding
        std::ostringstream escaped;
        for (char c : str) {
            if (std::isalnum(static_cast<unsigned char>(c)) || c == '-' || c == '_' || c == '.' || c == '~') {
                escaped << c;
            } else {
                escaped << '%' << std::hex << std::setw(2) << std::setfill('0')
                        << static_cast<int>(static_cast<unsigned char>(c));
            }
        }
        return escaped.str();
    }
};

// ============================================================================
// Google Fact Check Tools Provider
// ============================================================================

struct FactCheckProvider : YallaProviderAdapter {
    std::string base_url = "https://factchecktools.googleapis.com/v1alpha1/claims:search";
    std::string api_key;

    FactCheckProvider(const YallaProviderConfig& cfg) : YallaProviderAdapter(cfg) {
        if (config.api_key) api_key = config.api_key;
        if (config.base_url) base_url = config.base_url;
    }

    std::vector<YallaProviderArticle> fetch_articles(const std::string& query, int32_t max_results) override {
        std::vector<YallaProviderArticle> articles;

        if (api_key.empty()) return articles; // Requires API key

        std::string cache_key = build_cache_key("factcheck_search", query + "|" + std::to_string(max_results));
        std::string cached = cache.get(cache_key);

        std::string response;
        if (!cached.empty()) {
            response = cached;
        } else {
            rate_limiter.wait_if_needed();
            std::string url = base_url + "?key=" + api_key +
                             "&query=" + curl_escape(query) +
                             "&pageSize=" + std::to_string(max_results) +
                             "&languageCode=en";
            response = http.get(url);
            if (!response.empty()) {
                cache.set(cache_key, response, 3600); // 1 hour cache
            }
        }

        if (response.empty()) return articles;

        return parse_factcheck_response(response, max_results);
    }

    std::vector<YallaProviderArticle> fetch_latest(int32_t max_results) override {
        // For fact-check, "latest" means recent claims about trending topics
        return fetch_articles("trending", max_results);
    }

private:
    std::vector<YallaProviderArticle> parse_factcheck_response(const std::string& json_str, int max_results) {
        std::vector<YallaProviderArticle> articles;
        try {
            auto data = json::parse(json_str);
            if (!data.contains("claims") || !data["claims"].is_array()) return articles;

            int count = 0;
            for (const auto& claim : data["claims"]) {
                if (count >= max_results) break;

                std::string text = claim.value("text", "");
                std::string claimant = claim.value("claimant", "");
                auto claim_reviews = claim.value("claimReview", json::array());

                for (const auto& review : claim_reviews) {
                    std::string url = review.value("url", "");
                    std::string title = review.value("title", "");
                    std::string publisher = review.value("publisher.name", "");
                    std::string rating = review.value("textualRating", "");
                    std::string review_date = review.value("reviewDate", "");

                    if (url.empty()) continue;

                    YallaProviderArticle article{};
                    article.url = strdup(url.c_str());
                    article.title = strdup(("Fact Check: " + title).c_str());
                    article.summary = strdup(("Claim: " + text + " | Rating: " + rating).c_str());
                    article.content = strdup("");
                    article.image_url = strdup("");
                    article.category = strdup("factcheck");
                    article.sentiment = 0.0;
                    article.keywords = strdup((text + "," + claimant).c_str());
                    article.language = strdup("en");
                    article.publish_date = parse_iso_date(review_date);
                    article.author = strdup(publisher.c_str());
                    article.source_url = strdup("https://toolbox.google.com/factcheck/explorer");
                    article.provider_id = strdup(config.provider_id ? config.provider_id : "factcheck");
                    article.provider_name = strdup("Google Fact Check Tools");
                    article.license = strdup("Creative Commons Attribution 4.0");
                    article.attribution_url = strdup(url.c_str());
                    article.raw_provider_data = strdup(review.dump().c_str());

                    articles.push_back(article);
                    if (++count >= max_results) break;
                }
            }
        } catch (...) {}
        return articles;
    }

    int64_t parse_iso_date(const std::string& date_str) {
        // Parse ISO 8601 date
        // Simplified - in production use proper date parser
        return std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::system_clock::now().time_since_epoch()).count();
    }

    std::string curl_escape(const std::string& str) {
        std::ostringstream escaped;
        for (char c : str) {
            if (std::isalnum(static_cast<unsigned char>(c)) || c == '-' || c == '_' || c == '.' || c == '~') {
                escaped << c;
            } else {
                escaped << '%' << std::hex << std::setw(2) << std::setfill('0')
                        << static_cast<int>(static_cast<unsigned char>(c));
            }
        }
        return escaped.str();
    }
};

// ============================================================================
// Wikimedia Provider
// ============================================================================

struct WikimediaProvider : YallaProviderAdapter {
    std::string base_url = "https://en.wikipedia.org/w/api.php";

    WikimediaProvider(const YallaProviderConfig& cfg) : YallaProviderAdapter(cfg) {
        if (config.base_url) base_url = config.base_url;
    }

    std::vector<YallaProviderArticle> fetch_articles(const std::string& query, int32_t max_results) override {
        std::vector<YallaProviderArticle> articles;

        std::string cache_key = build_cache_key("wikimedia_search", query + "|" + std::to_string(max_results));
        std::string cached = cache.get(cache_key);

        std::string response;
        if (!cached.empty()) {
            response = cached;
        } else {
            rate_limiter.wait_if_needed();
            std::string url = base_url + "?action=query&list=search&srsearch=" + curl_escape(query) +
                             "&srlimit=" + std::to_string(max_results) + "&format=json";
            response = http.get(url);
            if (!response.empty()) {
                cache.set(cache_key, response, 86400); // 24 hour cache
            }
        }

        if (response.empty()) return articles;

        return parse_wikimedia_search(response, max_results);
    }

    std::vector<YallaProviderArticle> fetch_latest(int32_t max_results) override {
        // Get featured articles
        return fetch_articles("featured article", max_results);
    }

private:
    std::vector<YallaProviderArticle> parse_wikimedia_search(const std::string& json_str, int max_results) {
        std::vector<YallaProviderArticle> articles;
        try {
            auto data = json::parse(json_str);
            if (!data.contains("query") || !data["query"].contains("search")) return articles;

            int count = 0;
            for (const auto& item : data["query"]["search"]) {
                if (count >= max_results) break;

                std::string title = item.value("title", "");
                std::string snippet = item.value("snippet", "");
                int pageid = item.value("pageid", 0);

                if (title.empty() || pageid == 0) continue;

                std::string url = "https://en.wikipedia.org/?curid=" + std::to_string(pageid);

                YallaProviderArticle article{};
                article.url = strdup(url.c_str());
                article.title = strdup(title.c_str());
                article.summary = strdup(clean_snippet(snippet).c_str());
                article.content = strdup("");
                article.image_url = strdup("");
                article.category = strdup("reference");
                article.sentiment = 0.0;
                article.keywords = strdup(title.c_str());
                article.language = strdup("en");
                article.publish_date = std::chrono::duration_cast<std::chrono::milliseconds>(
                    std::chrono::system_clock::now().time_since_epoch()).count();
                article.author = strdup("Wikipedia Contributors");
                article.source_url = strdup("https://wikipedia.org");
                article.provider_id = strdup(config.provider_id ? config.provider_id : "wikimedia");
                article.provider_name = strdup("Wikimedia/Wikipedia");
                article.license = strdup("CC BY-SA 3.0");
                article.attribution_url = strdup(url.c_str());
                article.raw_provider_data = strdup(item.dump().c_str());

                articles.push_back(article);
                count++;
            }
        } catch (...) {}
        return articles;
    }

    std::string clean_snippet(const std::string& snippet) {
        std::string clean = snippet;
        clean = std::regex_replace(clean, std::regex("<[^>]+>"), "");
        clean = std::regex_replace(clean, std::regex("&[a-z]+;"), "");
        return clean;
    }

    std::string curl_escape(const std::string& str) {
        std::ostringstream escaped;
        for (char c : str) {
            if (std::isalnum(static_cast<unsigned char>(c)) || c == '-' || c == '_' || c == '.' || c == '~') {
                escaped << c;
            } else {
                escaped << '%' << std::hex << std::setw(2) << std::setfill('0')
                        << static_cast<int>(static_cast<unsigned char>(c));
            }
        }
        return escaped.str();
    }
};

// ============================================================================
// Provider Factory
// ============================================================================

struct ProviderFactory {
    static YallaProviderAdapter* create(const YallaProviderConfig& config) {
        if (!config.provider_id) return nullptr;

        std::string type_str;
        switch (config.type) {
            case YALLA_PROVIDER_RSS:
            case YALLA_PROVIDER_ATOM:
                return new RssProvider(config);
            case YALLA_PROVIDER_GDELT:
                return new GdeltProvider(config);
            case YALLA_PROVIDER_FACTCHECK:
                return new FactCheckProvider(config);
            case YALLA_PROVIDER_WIKIMEDIA:
                return new WikimediaProvider(config);
            default:
                return nullptr;
        }
    }
};

// ============================================================================
// C API Implementation
// ============================================================================

// Global provider instances (in production, use proper lifecycle management)
static std::unordered_map<std::string, YallaProviderAdapter*> g_providers;
static std::mutex g_providers_mutex;

extern "C" {

YALLA_CORE_EXPORT YallaProviderAdapterHandle yalla_provider_adapter_create(const YallaProviderConfig* config) {
    if (!config) return nullptr;
    auto* adapter = ProviderFactory::create(*config);
    if (!adapter) return nullptr;

    std::string id = config->provider_id ? config->provider_id : "unknown";
    std::lock_guard<std::mutex> lock(g_providers_mutex);
    g_providers[id] = adapter;
    return reinterpret_cast<YallaProviderAdapterHandle>(adapter);
}

YALLA_CORE_EXPORT void yalla_provider_adapter_destroy(YallaProviderAdapterHandle handle) {
    if (!handle) return;
    auto* adapter = reinterpret_cast<YallaProviderAdapter*>(handle);

    // Remove from global map
    std::lock_guard<std::mutex> lock(g_providers_mutex);
    for (auto it = g_providers.begin(); it != g_providers.end(); ++it) {
        if (it->second == adapter) {
            g_providers.erase(it);
            break;
        }
    }
    delete adapter;
}

YALLA_CORE_EXPORT YallaProviderResult yalla_provider_adapter_fetch(YallaProviderAdapterHandle handle,
    const char* query, int32_t max_results) {
    YallaProviderResult result{};
    result.success = false;
    result.error_message = nullptr;
    result.articles = nullptr;
    result.article_count = 0;
    result.next_cursor = 0;

    if (!handle) {
        result.error_message = strdup("Invalid adapter handle");
        return result;
    }

    auto* adapter = reinterpret_cast<YallaProviderAdapter*>(handle);
    std::string q = query ? query : "";

    try {
        auto articles = adapter->fetch_articles(q, max_results > 0 ? max_results : 50);
        result.success = true;
        result.article_count = static_cast<int32_t>(articles.size());

        if (!articles.empty()) {
            result.articles = new YallaProviderArticle[articles.size()];
            for (size_t i = 0; i < articles.size(); ++i) {
                result.articles[i] = articles[i];
            }
        }
    } catch (const std::exception& e) {
        result.error_message = strdup(e.what());
    } catch (...) {
        result.error_message = strdup("Unknown error");
    }

    return result;
}

YALLA_CORE_EXPORT YallaProviderResult yalla_provider_adapter_fetch_latest(YallaProviderAdapterHandle handle,
    int32_t max_results) {
    YallaProviderResult result{};
    result.success = false;
    result.error_message = nullptr;
    result.articles = nullptr;
    result.article_count = 0;
    result.next_cursor = 0;

    if (!handle) {
        result.error_message = strdup("Invalid adapter handle");
        return result;
    }

    auto* adapter = reinterpret_cast<YallaProviderAdapter*>(handle);

    try {
        auto articles = adapter->fetch_latest(max_results > 0 ? max_results : 50);
        result.success = true;
        result.article_count = static_cast<int32_t>(articles.size());

        if (!articles.empty()) {
            result.articles = new YallaProviderArticle[articles.size()];
            for (size_t i = 0; i < articles.size(); ++i) {
                result.articles[i] = articles[i];
            }
        }
    } catch (const std::exception& e) {
        result.error_message = strdup(e.what());
    } catch (...) {
        result.error_message = strdup("Unknown error");
    }

    return result;
}

YALLA_CORE_EXPORT void yalla_provider_adapter_free_result(YallaProviderResult* result) {
    if (!result) return;
    if (result->articles) {
        for (int i = 0; i < result->article_count; ++i) {
            auto& a = result->articles[i];
            free(const_cast<char*>(a.url));
            free(const_cast<char*>(a.title));
            free(const_cast<char*>(a.summary));
            free(const_cast<char*>(a.content));
            free(const_cast<char*>(a.image_url));
            free(const_cast<char*>(a.category));
            free(const_cast<char*>(a.keywords));
            free(const_cast<char*>(a.language));
            free(const_cast<char*>(a.author));
            free(const_cast<char*>(a.source_url));
            free(const_cast<char*>(a.provider_id));
            free(const_cast<char*>(a.provider_name));
            free(const_cast<char*>(a.license));
            free(const_cast<char*>(a.attribution_url));
            free(const_cast<char*>(a.raw_provider_data));
        }
        delete[] result->articles;
    }
    free(const_cast<char*>(result->error_message));
    result->articles = nullptr;
    result->article_count = 0;
    result->error_message = nullptr;
}

YALLA_CORE_EXPORT const char** yalla_provider_list_supported(int32_t* count) {
    if (!count) return nullptr;
    static const char* providers[] = {
        "rss", "atom", "gdelt", "factcheck", "wikimedia"
    };
    *count = 5;
    const char** result = new const char*[5];
    for (int i = 0; i < 5; ++i) {
        result[i] = strdup(providers[i]);
    }
    return result;
}

YALLA_CORE_EXPORT void yalla_provider_free_list(const char** list, int32_t count) {
    if (!list) return;
    for (int i = 0; i < count; ++i) {
        free(const_cast<char*>(list[i]));
    }
    delete[] list;
}

} // extern "C"