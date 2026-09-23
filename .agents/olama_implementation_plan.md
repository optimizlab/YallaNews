# News Gathering, Subject Grouping & Article Blender System (Ollama TinyLLM Edition)

## Summary

This plan replaces the basic TF-IDF clustering with a **Real Embedded TinyLLM (Ollama)** integration. The system will use local LLMs (like `nomic-embed-text`, `llama3.2`, or `gemma`) to semantically cluster articles and intelligently blend them.

When news articles are crawled:
1. **Semantic Clustering**: The app fetches dense vector embeddings from a local Ollama instance for each article's title and summary. Articles are grouped strictly using high-dimensional cosine similarity, eliminating false positives (like grouping "Elections" with "Women's Day").
2. **Generative Blending**: The app uses Ollama's text generation API to intelligently synthesize a cohesive master title, extract true highlights, and write a unified executive lead from the source articles.
3. **Fallback Mechanism**: If Ollama is not running, the system gracefully falls back to the legacy TF-IDF/heuristic methods.

## User Review Required
> [!WARNING]
> This requires you to have [Ollama](https://ollama.com/) running locally on your machine. By default, it will look for `http://localhost:11434`.

> [!NOTE]
> Based on your request for limited resources, we will use **`nomic-embed-text`** for embeddings (very fast and tiny) and **`gemma:2b`** for the generative blender (lightweight but powerful enough for summarization).
> We will also build a **Settings Page** so you can easily change these models or the Ollama URL at any time!

## Proposed Changes

### 1. Settings Page for Ollama Configuration
#### [NEW] [settings_page.dart](file:///d:/FLUTTER_PROJECTS/YallaNews/lib/views/settings_page.dart) & `settings_service.dart`
- A new page accessible from the sidebar/menu.
- Fields to configure:
  - **Ollama API URL** (default: `http://localhost:11434`)
  - **Embedding Model** (default: `nomic-embed-text`)
  - **Generation Model** (default: `gemma:2b`)
- Persists settings using `SharedPreferences`.
### 1. Ollama Integration Service
#### [NEW] [ollama_service.dart](file:///d:/FLUTTER_PROJECTS/YallaNews/lib/services/ollama_service.dart)
- A dedicated service to communicate with the local Ollama API.
- `getEmbedding(String text, {String model})`: Calls `/api/embeddings` to get dense vectors.
- `generateText(String prompt, {String model})`: Calls `/api/generate` to synthesize blended titles and summaries.

### 2. Subject Grouping & Clustering Engine
#### [MODIFY] [news_grouping_service.dart](file:///d:/FLUTTER_PROJECTS/YallaNews/lib/services/news_grouping_service.dart) & [semantic_cluster.dart](file:///d:/FLUTTER_PROJECTS/YallaNews/lib/services/semantic_cluster.dart)
- Overhaul `calculateSimilarity()` to use `OllamaService.getEmbedding`.
- Compute high-dimensional Cosine Similarity.
- Set a strict threshold (e.g., `> 0.82`) to ensure only truly identical news events are clustered together.
- Keep the existing TF-IDF logic *only* as a fallback if Ollama is unreachable.

### 3. Generative News Blender
#### [MODIFY] [news_blender_service.dart](file:///d:/FLUTTER_PROJECTS/YallaNews/lib/services/news_blender_service.dart)
- **Generative Title**: Prompt Ollama to read all source titles and generate a single, professional, clickbait-free Arabic headline.
- **Generative Lead & Highlights**: Prompt Ollama with the source contents to generate a unified summary and extract bullet points.
- **Generative Content Paragraphs**: Use Ollama to re-write and synthesize the raw crawled text into rich, well-structured paragraphs, seamlessly integrating with the existing MSN image injection.
- Preserve source attribution logic (source counts, original links, etc.).

## Verification Plan

### Automated Tests
- Test connection to `localhost:11434`.
- Validate that unrelated articles (like the ones in your screenshot) yield low embedding similarity (< 0.5) and are NOT grouped.

### Manual Verification
- Run the app with Ollama running in the background.
- Verify the Home Feed clusters are 100% accurate.
- Check the blended article detail page to see the AI-generated title and summaries.

