#ifndef YALLA_TOKENIZER_H
#define YALLA_TOKENIZER_H

#include <cstddef>
#include <string>
#include <vector>

namespace yalla {

// Simple Unicode-aware tokenizer producing words and sentences. Bounded output
// suitable for the working-memory budget.
class Tokenizer {
public:
    // Split text into words (maximal runs of letters), honoring Arabic UTF-8.
    static std::vector<std::string> tokenize_words(const std::string& text, size_t max_tokens = 4096);

    // Split text into sentences on sentence-final punctuation.
    static std::vector<std::string> tokenize_sentences(const std::string& text, size_t max_sentences = 1024);
};

} // namespace yalla

#endif // YALLA_TOKENIZER_H
