#ifndef HTTP_FETCHER_H
#define HTTP_FETCHER_H

#include <string>
#include <functional>
#include "news_brain.h"

namespace newsbrain {

class HttpFetcher {
public:
    static HttpFetcher& instance();

    // Sets custom fetcher callback (e.g. from Dart / Android / iOS platform)
    void setExternalFetcher(NewsBrainHttpFetchCallback callback);

    // Fetches URL and returns HTML response string. Throws or returns empty on error.
    std::string fetch(const std::string& url);

private:
    HttpFetcher() = default;
    ~HttpFetcher() = default;

    NewsBrainHttpFetchCallback externalCallback_ = nullptr;

#ifdef _WIN32
    std::string fetchWinHttp(const std::string& url);
#endif
};

} // namespace newsbrain

#endif // HTTP_FETCHER_H
