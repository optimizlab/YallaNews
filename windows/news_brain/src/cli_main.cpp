#include "../include/news_brain.h"
#include <iostream>
#include <fstream>
#include <sstream>
#include <string>

int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cout << "========================================\n"
                  << "  newsBrain Native Engine CLI (v" << newsbrain_get_version() << ")\n"
                  << "========================================\n"
                  << "Usage:\n"
                  << "  news_brain_cli scan <url>\n"
                  << "  news_brain_cli extract <url>\n"
                  << "  news_brain_cli scan-file <file.html> [url]\n"
                  << "  news_brain_cli extract-file <file.html> [url]\n"
                  << "  news_brain_cli version\n";
        return 0;
    }

    std::string cmd = argv[1];

    if (cmd == "version") {
        std::cout << newsbrain_get_version() << "\n";
        return 0;
    }

    if (cmd == "scan" && argc >= 3) {
        std::string url = argv[2];
        std::cout << "[newsBrain] Scanning URL: " << url << " ...\n";
        const char* result = newsbrain_scan_url(url.c_str());
        if (result != nullptr) {
            std::cout << result << "\n";
            newsbrain_free_string(result);
        } else {
            std::cerr << "[ERROR] Scan returned null.\n";
            return 1;
        }
        return 0;
    }

    if (cmd == "extract" && argc >= 3) {
        std::string url = argv[2];
        std::cout << "[newsBrain] Extracting article from URL: " << url << " ...\n";
        const char* result = newsbrain_extract_article_url(url.c_str());
        if (result != nullptr) {
            std::cout << result << "\n";
            newsbrain_free_string(result);
        } else {
            std::cerr << "[ERROR] Extract returned null.\n";
            return 1;
        }
        return 0;
    }

    if (cmd == "scan-file" && argc >= 3) {
        std::string filePath = argv[2];
        std::string url = (argc >= 4) ? argv[3] : "file://" + filePath;
        std::ifstream file(filePath);
        if (!file.is_open()) {
            std::cerr << "[ERROR] Cannot open file: " << filePath << "\n";
            return 1;
        }
        std::stringstream buffer;
        buffer << file.rdbuf();
        std::string html = buffer.str();

        std::cout << "[newsBrain] Scanning local HTML (" << html.length() << " bytes)...\n";
        const char* result = newsbrain_scan_html(html.c_str(), url.c_str());
        if (result != nullptr) {
            std::cout << result << "\n";
            newsbrain_free_string(result);
        }
        return 0;
    }

    if (cmd == "extract-file" && argc >= 3) {
        std::string filePath = argv[2];
        std::string url = (argc >= 4) ? argv[3] : "file://" + filePath;
        std::ifstream file(filePath);
        if (!file.is_open()) {
            std::cerr << "[ERROR] Cannot open file: " << filePath << "\n";
            return 1;
        }
        std::stringstream buffer;
        buffer << file.rdbuf();
        std::string html = buffer.str();

        std::cout << "[newsBrain] Extracting article from local HTML (" << html.length() << " bytes)...\n";
        const char* result = newsbrain_extract_article_html(html.c_str(), url.c_str());
        if (result != nullptr) {
            std::cout << result << "\n";
            newsbrain_free_string(result);
        }
        return 0;
    }

    std::cerr << "Unknown command: " << cmd << "\n";
    return 1;
}
