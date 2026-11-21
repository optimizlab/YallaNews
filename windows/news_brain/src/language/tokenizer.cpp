#include "tokenizer.h"

#include <cctype>

namespace yalla {

bool is_letter(char c) {
    unsigned char uc = (unsigned char)c;
    if (std::isalpha(uc)) return true;
    // Arabic UTF-8 trail bytes are letters by virtue of being in a 2-byte seq.
    return (unsigned char)c >= 0x80;
}

std::vector<std::string> Tokenizer::tokenize_words(const std::string& text, size_t max_tokens) {
    std::vector<std::string> tokens;
    tokens.reserve(std::min(max_tokens, size_t(256)));
    std::string cur;
    for (size_t i = 0; i < text.size(); ++i) {
        char c = text[i];
        if (is_letter(c)) {
            cur += c;
        } else {
            if (!cur.empty()) { tokens.push_back(cur); cur.clear(); if (tokens.size() >= max_tokens) break; }
        }
    }
    if (!cur.empty() && tokens.size() < max_tokens) tokens.push_back(cur);
    return tokens;
}

std::vector<std::string> Tokenizer::tokenize_sentences(const std::string& text, size_t max_sentences) {
    std::vector<std::string> sentences;
    sentences.reserve(std::min(max_sentences, size_t(64)));
    std::string cur;
    for (size_t i = 0; i < text.size(); ++i) {
        char c = text[i];
        cur += c;
        if (c == '.' || c == '!' || c == '?') {
            // trim
            size_t a = cur.find_first_not_of(" \t\r\n");
            size_t b = cur.find_last_not_of(" \t\r\n");
            if (a != std::string::npos && b != std::string::npos) {
                sentences.push_back(cur.substr(a, b - a + 1));
                if (sentences.size() >= max_sentences) break;
            }
            cur.clear();
        }
    }
    if (!cur.empty() && sentences.size() < max_sentences) {
        size_t a = cur.find_first_not_of(" \t\r\n");
        size_t b = cur.find_last_not_of(" \t\r\n");
        if (a != std::string::npos && b != std::string::npos)
            sentences.push_back(cur.substr(a, b - a + 1));
    }
    return sentences;
}

} // namespace yalla
