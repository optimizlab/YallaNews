#include "../include/http_fetcher.h"
#include <iostream>
#include <sstream>
#include <vector>

#ifdef _WIN32
#include <windows.h>
#include <winhttp.h>
#pragma comment(lib, "winhttp.lib")
#endif

namespace newsbrain {

HttpFetcher& HttpFetcher::instance() {
    static HttpFetcher fetcher;
    return fetcher;
}

void HttpFetcher::setExternalFetcher(NewsBrainHttpFetchCallback callback) {
    externalCallback_ = callback;
}

std::string HttpFetcher::fetch(const std::string& url) {
    if (externalCallback_ != nullptr) {
        const char* result = externalCallback_(url.c_str());
        if (result != nullptr) {
            std::string content(result);
            return content;
        }
    }

#ifdef _WIN32
    return fetchWinHttp(url);
#else
    std::cerr << "[newsBrain] No external HTTP fetcher set on non-Windows platform for: " << url << std::endl;
    return "";
#endif
}

#ifdef _WIN32
std::string HttpFetcher::fetchWinHttp(const std::string& url) {
    std::string response;

    URL_COMPONENTS urlComp;
    ZeroMemory(&urlComp, sizeof(urlComp));
    urlComp.dwStructSize = sizeof(urlComp);

    wchar_t hostName[256] = {0};
    wchar_t urlPath[2048] = {0};

    urlComp.lpszHostName = hostName;
    urlComp.dwHostNameLength = sizeof(hostName) / sizeof(wchar_t);
    urlComp.lpszUrlPath = urlPath;
    urlComp.dwUrlPathLength = sizeof(urlPath) / sizeof(wchar_t);

    int wideLen = MultiByteToWideChar(CP_UTF8, 0, url.c_str(), -1, nullptr, 0);
    if (wideLen <= 0) return "";
    std::vector<wchar_t> wUrl(wideLen);
    MultiByteToWideChar(CP_UTF8, 0, url.c_str(), -1, wUrl.data(), wideLen);

    if (!WinHttpCrackUrl(wUrl.data(), 0, 0, &urlComp)) {
        return "";
    }

    HINTERNET hSession = WinHttpOpen(
        L"NewsBrain/1.0 (Windows NT 10.0; Win64; x64) Mobile/Desktop",
        WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
        WINHTTP_NO_PROXY_NAME,
        WINHTTP_NO_PROXY_BYPASS,
        0
    );
    if (!hSession) return "";

    // Set timeouts (10 seconds)
    WinHttpSetTimeouts(hSession, 5000, 5000, 10000, 10000);

    INTERNET_PORT port = urlComp.nPort;
    HINTERNET hConnect = WinHttpConnect(hSession, urlComp.lpszHostName, port, 0);
    if (!hConnect) {
        WinHttpCloseHandle(hSession);
        return "";
    }

    DWORD flags = (urlComp.nScheme == INTERNET_SCHEME_HTTPS) ? WINHTTP_FLAG_SECURE : 0;
    HINTERNET hRequest = WinHttpOpenRequest(
        hConnect,
        L"GET",
        urlComp.lpszUrlPath,
        nullptr,
        WINHTTP_NO_REFERER,
        WINHTTP_DEFAULT_ACCEPT_TYPES,
        flags
    );

    if (!hRequest) {
        WinHttpCloseHandle(hConnect);
        WinHttpCloseHandle(hSession);
        return "";
    }

    // Auto redirect
    DWORD redirectOption = WINHTTP_OPTION_REDIRECT_POLICY_ALWAYS;
    WinHttpSetOption(hRequest, WINHTTP_OPTION_REDIRECT_POLICY, &redirectOption, sizeof(redirectOption));

    // Headers
    LPCWSTR headers = L"User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36 NewsBrain/1.0\r\nAccept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8\r\nAccept-Language: ar,en-US,en;q=0.9\r\n";
    WinHttpAddRequestHeaders(hRequest, headers, -1L, WINHTTP_ADDREQ_FLAG_ADD | WINHTTP_ADDREQ_FLAG_REPLACE);

    BOOL bResults = WinHttpSendRequest(
        hRequest,
        WINHTTP_NO_ADDITIONAL_HEADERS,
        0,
        WINHTTP_NO_REQUEST_DATA,
        0,
        0,
        0
    );

    if (bResults) {
        bResults = WinHttpReceiveResponse(hRequest, nullptr);
    }

    if (bResults) {
        DWORD dwSize = 0;
        std::vector<char> buffer;
        do {
            dwSize = 0;
            if (!WinHttpQueryDataAvailable(hRequest, &dwSize)) break;
            if (dwSize == 0) break;

            size_t currentSize = buffer.size();
            buffer.resize(currentSize + dwSize);
            DWORD dwDownloaded = 0;
            if (WinHttpReadData(hRequest, buffer.data() + currentSize, dwSize, &dwDownloaded)) {
                buffer.resize(currentSize + dwDownloaded);
            } else {
                break;
            }
        } while (dwSize > 0);

        if (!buffer.empty()) {
            response.assign(buffer.begin(), buffer.end());
        }
    }

    WinHttpCloseHandle(hRequest);
    WinHttpCloseHandle(hConnect);
    WinHttpCloseHandle(hSession);

    return response;
}
#endif

} // namespace newsbrain
