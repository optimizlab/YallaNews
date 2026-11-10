# YallaNews FFI Signature Documentation

**Generated**: 2026-11-09
**Purpose**: Complete inventory of all existing FFI signatures for migration planning

---

## 1. yalla_engine (Windows/yalla_engine)

### C++ Header: `windows/yalla_engine/yalla_engine.h`

| Function | Signature | Return | Description |
|----------|-----------|--------|-------------|
| `init_engine` | `void init_engine(const char* db_content_json)` | `void` | Initialize engine with JSON database |
| `process_url` | `const char* process_url(const char* url)` | `const char*` | Main pipeline: URL → article JSON |
| `free_string` | `void free_string(const char* str)` | `void` | Free string allocated by engine |
| `get_engine_logs` | `const char* get_engine_logs()` | `const char*` | Get accumulated logs |
| `clear_engine_logs` | `void clear_engine_logs()` | `void` | Clear log buffer |
| `analyze_article` | `const char* analyze_article(const char* json_input)` | `const char*` | Full NLP analysis → JSON |
| `cluster_articles_ex` | `const char* cluster_articles_ex(const char* json_input, int32_t algorithm, int32_t n_clusters, double eps, int32_t min_samples)` | `const char*` | Clustering with algorithm selection |
| `free_cluster_string` | `void free_cluster_string(const char* str)` | `void` | Free cluster result string |
| `is_valid_image_url` | `int is_valid_image_url(const char* url)` | `int` | Validate image URL (0/1) |
| `validate_image_relevance` | `const char* validate_image_relevance(const char* title, const char* description, const char* content, const char* image_url)` | `const char*` | Score image relevance → JSON |
| `split_paragraphs_by_dots` | `const char* split_paragraphs_by_dots(const char* content)` | `const char*` | Split content → JSON array |
| `clean_article_content` | `const char* clean_article_content(const char* title, const char* content)` | `const char*` | TinyLLM-style cleaning → JSON |
| `extract_story_elements` | `const char* extract_story_elements(const char* title, const char* content)` | `const char*` | Extract persons/dates/events → JSON |
| `optimize_sentiment` | `double optimize_sentiment(const char* text)` | `double` | Sentiment score [-1, 1] |

### Dart FFI Bindings: `lib/services/yalla_ffi_io.dart`

```dart
// Typedefs
typedef InitEngineCSig = Void Function(Pointer<Utf8> dbContent);
typedef ProcessUrlCSig = Pointer<Utf8> Function(Pointer<Utf8> url);
typedef AnalyzeArticleCSig = Pointer<Utf8> Function(Pointer<Utf8> jsonInput);
typedef FreeStringCSig = Void Function(Pointer<Utf8> str);
typedef GetLogsCSig = Pointer<Utf8> Function();
typedef ClearLogsCSig = Void Function();

// Service Methods
static void initEngine(String dbContentJson)
static String processUrl(String url)
static String analyzeArticle(String jsonInput)
static String getLogs()
static void clearLogs()
static String clusterAndSummarize(String jsonInput)  // NOT in C++ header!
```

**Note**: `cluster_and_summarize` is called in Dart but NOT declared in `yalla_engine.h` - this is a missing symbol.

---

## 2. news_brain (Windows/news_brain)

### C++ Header: `windows/news_brain/include/news_brain.h`

| Function | Signature | Return | Description |
|----------|-----------|--------|-------------|
| `newsbrain_get_version` | `const char* newsbrain_get_version()` | `const char*` | Library version string |
| `newsbrain_free_string` | `void newsbrain_free_string(const char* str)` | `void` | Free string from newsBrain |
| `newsbrain_scan_url` | `const char* newsbrain_scan_url(const char* url)` | `const char*` | URL → PageSkeleton JSON |
| `newsbrain_scan_html` | `const char* newsbrain_scan_html(const char* html, const char* url)` | `const char*` | HTML → PageSkeleton JSON |
| `newsbrain_extract_article_url` | `const char* newsbrain_extract_article_url(const char* url)` | `const char*` | URL → NewsArticle JSON |
| `newsbrain_extract_article_html` | `const char* newsbrain_extract_article_html(const char* html, const char* url)` | `const char*` | HTML → NewsArticle JSON |
| `newsbrain_set_http_fetcher` | `void newsbrain_set_http_fetcher(NewsBrainHttpFetchCallback callback)` | `void` | Set platform HTTP fetcher |
| `newsbrain_classify_article` | `const char* newsbrain_classify_article(const char* title, const char* content, const char* summary)` | `const char*` | Classify → JSON (category, sentiment, entities) |
| `newsbrain_classify_category` | `const char* newsbrain_classify_category(const char* title, const char* content, const char* summary)` | `const char*` | Category only |
| `newsbrain_analyze_sentiment` | `double newsbrain_analyze_sentiment(const char* text)` | `double` | Sentiment [-1, 1] |
| `newsbrain_score_article_quality` | `double newsbrain_score_article_quality(const char* title, const char* content, const char* summary)` | `double` | Quality score [0, 1] |

### Dart FFI Bindings: `lib/services/news_brain_ffi.dart`

```dart
// Typedefs
typedef _GetVersionC = Pointer<Utf8> Function();
typedef _FreeStringC = Void Function(Pointer<Utf8> str);
typedef _ScanUrlC = Pointer<Utf8> Function(Pointer<Utf8> url);
typedef _ScanHtmlC = Pointer<Utf8> Function(Pointer<Utf8> html, Pointer<Utf8> url);
typedef _ExtractArticleUrlC = Pointer<Utf8> Function(Pointer<Utf8> url);
typedef _ExtractArticleHtmlC = Pointer<Utf8> Function(Pointer<Utf8> html, Pointer<Utf8> url);
typedef _ClassifyArticleC = Pointer<Utf8> Function(Pointer<Utf8> title, Pointer<Utf8> content, Pointer<Utf8> summary);
typedef _ClassifyCategoryC = Pointer<Utf8> Function(Pointer<Utf8> title, Pointer<Utf8> content, Pointer<Utf8> summary);
typedef _AnalyzeSentimentC = Double Function(Pointer<Utf8> text);

// Service Methods
String getVersion()
Future<PageSkeleton?> scanUrl(String url)
Future<PageSkeleton?> scanHtml(String html, {String url = ''})
Future<NewsArticle?> extractArticleUrl(String url)
Future<NewsArticle?> extractArticleHtml(String html, {String url = ''})
Future<Map<String, dynamic>?> classifyArticle(String title, String content, String summary)
Future<String?> classifyCategory(String title, String content, String summary)
Future<double> analyzeSentiment(String text)
```

**Platform Note**: On non-Windows (Android/iOS), `scanUrl` and `extractArticleUrl` fetch HTML via Dart `http` package first, then call `scanHtml`/`extractArticleHtml`.

---

## 3. yalla_core (New Unified Core Module)

### C++ Header: `android/app/src/main/cpp/core/include/yalla_core.h`

#### Task Scheduler
| Function | Signature | Return | Description |
|----------|-----------|--------|-------------|
| `yalla_task_scheduler_create` | `YallaTaskSchedulerHandle yalla_task_scheduler_create(int32_t max_concurrent_tasks)` | `YallaTaskSchedulerHandle` | Create thread pool |
| `yalla_task_scheduler_destroy` | `void yalla_task_scheduler_destroy(YallaTaskSchedulerHandle)` | `void` | Destroy thread pool |
| `yalla_task_scheduler_submit` | `bool yalla_task_scheduler_submit(YallaTaskSchedulerHandle, const char* task_json, YallaCompletionCallback, void*)` | `bool` | Submit async task |
| `yalla_task_scheduler_cancel_all` | `void yalla_task_scheduler_cancel_all(YallaTaskSchedulerHandle)` | `void` | Cancel all pending tasks |
| `yalla_task_scheduler_pending_count` | `int32_t yalla_task_scheduler_pending_count(YallaTaskSchedulerHandle)` | `int32_t` | Get pending task count |

#### News Ingestion
| Function | Signature | Return | Description |
|----------|-----------|--------|-------------|
| `yalla_news_ingestion_create` | `YallaNewsIngestionHandle yalla_news_ingestion_create()` | `YallaNewsIngestionHandle` | Create ingestion handler |
| `yalla_news_ingestion_destroy` | `void yalla_news_ingestion_destroy(YallaNewsIngestionHandle)` | `void` | Destroy handler |
| `yalla_news_ingestion_fetch_rss` | `bool yalla_news_ingestion_fetch_rss(YallaNewsIngestionHandle, const char* feed_url, YallaCompletionCallback, void*)` | `bool` | Fetch RSS feed (async) |
| `yalla_news_ingestion_fetch_atom` | `bool yalla_news_ingestion_fetch_atom(YallaNewsIngestionHandle, const char* feed_url, YallaCompletionCallback, void*)` | `bool` | Fetch Atom feed (async) |
| `yalla_news_ingestion_extract_html` | `bool yalla_news_ingestion_extract_html(YallaNewsIngestionHandle, const char* url, const char* html, YallaCompletionCallback, void*)` | `bool` | Extract article from HTML (async) |
| `yalla_news_ingestion_set_timeout` | `void yalla_news_ingestion_set_timeout(YallaNewsIngestionHandle, int32_t timeout_ms)` | `void` | Set HTTP timeout |
| `yalla_news_ingestion_set_rate_limit` | `void yalla_news_ingestion_set_rate_limit(YallaNewsIngestionHandle, int32_t rpm)` | `void` | Set rate limit (requests/min) |

#### Language Detection
| Function | Signature | Return | Description |
|----------|-----------|--------|-------------|
| `yalla_language_detector_create` | `YallaLanguageDetectorHandle yalla_language_detector_create()` | `YallaLanguageDetectorHandle` | Create detector |
| `yalla_language_detector_destroy` | `void yalla_language_detector_destroy(YallaLanguageDetectorHandle)` | `void` | Destroy detector |
| `yalla_language_detector_detect` | `YallaLanguage yalla_language_detector_detect(YallaLanguageDetectorHandle, const char* text, float* confidence)` | `YallaLanguage` | Detect language (Ar/En/Fr) |
| `yalla_language_detector_normalize` | `const char* yalla_language_detector_normalize(YallaLanguageDetectorHandle, YallaLanguage, const char* text)` | `const char*` | Normalize text for language |

#### Deduplication
| Function | Signature | Return | Description |
|----------|-----------|--------|-------------|
| `yalla_deduplicator_create` | `YallaDeduplicatorHandle yalla_deduplicator_create()` | `YallaDeduplicatorHandle` | Create deduplicator |
| `yalla_deduplicator_destroy` | `void yalla_deduplicator_destroy(YallaDeduplicatorHandle)` | `void` | Destroy deduplicator |
| `yalla_deduplicator_is_duplicate` | `bool yalla_deduplicator_is_duplicate(YallaDeduplicatorHandle, const YallaArticle*, float* similarity)` | `bool` | Check exact/near duplicate |
| `yalla_deduplicator_add` | `void yalla_deduplicator_add(YallaDeduplicatorHandle, const YallaArticle*)` | `void` | Add article to index |
| `yalla_deduplicator_clear` | `void yalla_deduplicator_clear(YallaDeduplicatorHandle)` | `void` | Clear index |
| `yalla_deduplicator_set_threshold` | `void yalla_deduplicator_set_threshold(YallaDeduplicatorHandle, float threshold)` | `void` | Set Jaccard threshold |

#### Classification
| Function | Signature | Return | Description |
|----------|-----------|--------|-------------|
| `yalla_classifier_create` | `YallaClassifierHandle yalla_classifier_create()` | `YallaClassifierHandle` | Create classifier |
| `yalla_classifier_destroy` | `void yalla_classifier_destroy(YallaClassifierHandle)` | `void` | Destroy classifier |
| `yalla_classifier_classify` | `const char* yalla_classifier_classify(YallaClassifierHandle, const char* title, const char* content, const char* summary, float* confidence)` | `const char*` | Classify article (Ar/En/Fr) |
| `yalla_classifier_get_subcategory` | `const char* yalla_classifier_get_subcategory(YallaClassifierHandle, const char* title, const char* content, const char* summary)` | `const char*` | Get subcategory (football, AI, etc.) |

#### Entity Extraction
| Function | Signature | Return | Description |
|----------|-----------|--------|-------------|
| `yalla_entity_extractor_create` | `YallaEntityExtractorHandle yalla_entity_extractor_create()` | `YallaEntityExtractorHandle` | Create extractor |
| `yalla_entity_extractor_destroy` | `void yalla_entity_extractor_destroy(YallaEntityExtractorHandle)` | `void` | Destroy extractor |
| `yalla_entity_extractor_extract` | `YallaEntity* yalla_entity_extractor_extract(YallaEntityExtractorHandle, const char* title, const char* content, const char* language, int32_t* count)` | `YallaEntity*` | Extract entities (multilingual) |
| `yalla_entity_extractor_free_entities` | `void yalla_entity_extractor_free_entities(YallaEntity*, int32_t count)` | `void` | Free entity array |

#### Event Clustering
| Function | Signature | Return | Description |
|----------|-----------|--------|-------------|
| `yalla_event_clusterer_create` | `YallaEventClustererHandle yalla_event_clusterer_create()` | `YallaEventClustererHandle` | Create clusterer |
| `yalla_event_clusterer_destroy` | `void yalla_event_clusterer_destroy(YallaEventClustererHandle)` | `void` | Destroy clusterer |
| `yalla_event_clusterer_cluster` | `YallaCluster* yalla_event_clusterer_cluster(YallaEventClustererHandle, const YallaArticle*, int32_t, int32_t*)` | `YallaCluster*` | Cluster articles (DBSCAN) |
| `yalla_event_clusterer_cluster_ex` | `YallaCluster* yalla_event_clusterer_cluster_ex(YallaEventClustererHandle, const YallaArticle*, int32_t, int32_t, int32_t, double, int32_t, int32_t*)` | `YallaCluster*` | Cluster with algorithm choice |
| `yalla_event_clusterer_free_clusters` | `void yalla_event_clusterer_free_clusters(YallaCluster*, int32_t)` | `void` | Free cluster results |

#### Model Manager (llama.cpp)
| Function | Signature | Return | Description |
|----------|-----------|--------|-------------|
| `yalla_model_manager_create` | `YallaModelManagerHandle yalla_model_manager_create(const char* models_dir)` | `YallaModelManagerHandle` | Create model manager |
| `yalla_model_manager_destroy` | `void yalla_model_manager_destroy(YallaModelManagerHandle)` | `void` | Destroy manager |
| `yalla_model_manager_download` | `bool yalla_model_manager_download(YallaModelManagerHandle, const char* model_id, const char* url, const char* checksum, YallaProgressCallback, void*)` | `bool` | Download GGUF model |
| `yalla_model_manager_verify` | `bool yalla_model_manager_verify(YallaModelManagerHandle, const char* model_id, bool* verified)` | `bool` | Verify model exists |
| `yalla_model_manager_get_info` | `YallaModelInfo* yalla_model_manager_get_info(YallaModelManagerHandle, const char* model_id)` | `YallaModelInfo*` | Get model metadata |
| `yalla_model_manager_free_info` | `void yalla_model_manager_free_info(YallaModelInfo*)` | `void` | Free model info |
| `yalla_model_manager_list_models` | `const char** yalla_model_manager_list_models(YallaModelManagerHandle, int32_t*)` | `const char**` | List available models |
| `yalla_model_manager_free_list` | `void yalla_model_manager_free_list(const char**, int32_t)` | `void` | Free model list |
| `yalla_model_manager_unload` | `void yalla_model_manager_unload(YallaModelManagerHandle, const char* model_id)` | `void` | Unload model from cache |
| `yalla_model_manager_cancel_download` | `void yalla_model_manager_cancel_download(YallaModelManagerHandle)` | `void` | Cancel active download |

#### Inference Engine
| Function | Signature | Return | Description |
|----------|-----------|--------|-------------|
| `yalla_inference_engine_create` | `YallaInferenceEngineHandle yalla_inference_engine_create(YallaModelManagerHandle)` | `YallaInferenceEngineHandle` | Create inference engine |
| `yalla_inference_engine_destroy` | `void yalla_inference_engine_destroy(YallaInferenceEngineHandle)` | `void` | Destroy engine |
| `yalla_inference_engine_load_model` | `bool yalla_inference_engine_load_model(YallaInferenceEngineHandle, const char* model_id, int32_t ctx_size, int32_t max_batch)` | `bool` | Load GGUF into context |
| `yalla_inference_engine_unload_model` | `void yalla_inference_engine_unload_model(YallaInferenceEngineHandle)` | `void` | Unload model |
| `yalla_inference_engine_infer` | `YallaInferenceResponse yalla_inference_engine_infer(YallaInferenceEngineHandle, const YallaInferenceRequest*)` | `YallaInferenceResponse` | Run inference |
| `yalla_inference_engine_cancel` | `void yalla_inference_engine_cancel(YallaInferenceEngineHandle)` | `void` | Cancel generation |
| `yalla_inference_engine_is_busy` | `bool yalla_inference_engine_is_busy(YallaInferenceEngineHandle)` | `bool` | Check if busy |
| `yalla_inference_engine_get_memory_usage` | `int64_t yalla_inference_engine_get_memory_usage(YallaInferenceEngineHandle)` | `int64_t` | Estimate memory usage |
| `yalla_inference_engine_set_sampling_params` | `void yalla_inference_engine_set_sampling_params(YallaInferenceEngineHandle, float, float, int32_t, float, int32_t, float, float)` | `void` | Set sampling params |

#### Summarization
| Function | Signature | Return | Description |
|----------|-----------|--------|-------------|
| `yalla_summarizer_create` | `YallaSummarizerHandle yalla_summarizer_create(YallaInferenceEngineHandle)` | `YallaSummarizerHandle` | Create summarizer |
| `yalla_summarizer_destroy` | `void yalla_summarizer_destroy(YallaSummarizerHandle)` | `void` | Destroy summarizer |
| `yalla_summarizer_summarize` | `const char* yalla_summarizer_summarize(YallaSummarizerHandle, const char* title, const char* content, const char* language, int32_t max_length)` | `const char*` | Summarize article (Ar/En/Fr) |
| `yalla_summarizer_summarize_batch` | `const char* yalla_summarizer_summarize_batch(YallaSummarizerHandle, const char**, const char**, int32_t, const char*, int32_t)` | `const char*` | Batch summarize (JSON) |

#### Translation
| Function | Signature | Return | Description |
|----------|-----------|--------|-------------|
| `yalla_translator_create` | `YallaTranslatorHandle yalla_translator_create(YallaInferenceEngineHandle)` | `YallaTranslatorHandle` | Create translator |
| `yalla_translator_destroy` | `void yalla_translator_destroy(YallaTranslatorHandle)` | `void` | Destroy translator |
| `yalla_translator_translate` | `const char* yalla_translator_translate(YallaTranslatorHandle, const char* text, YallaLanguage source, YallaLanguage target)` | `const char*` | Translate text (Ar↔En↔Fr) |
| `yalla_translator_translate_batch` | `const char* yalla_translator_translate_batch(YallaTranslatorHandle, const char**, int32_t, YallaLanguage, YallaLanguage)` | `const char*` | Batch translate (JSON) |

#### Utility
| Function | Signature | Return | Description |
|----------|-----------|--------|-------------|
| `yalla_free_string` | `void yalla_free_string(const char* str)` | `void` | Free string from any function |
| `yalla_free_article` | `void yalla_free_article(YallaArticle* article)` | `void` | Free article struct |
| `yalla_get_version` | `const char* yalla_get_version()` | `const char*` | Get library version |
| `yalla_set_log_callback` | `void yalla_set_log_callback(YallaLogCallback, void*)` | `void` | Set log callback |

---

## 4. C++ NLP Structures (arabic_nlp.h)

```cpp
struct NerEntity {
    string type;
    string value;
    string canonical;
    double confidence;
};

struct ExtractedDate {
    string raw;
    string iso;
    double confidence;
};

struct SportsMatchData {
    string home_team, away_team, match_score, match_result;
    string sport_type, venue;
    vector<string> goal_scorers, injured_players, cards, transfers, standings;
};

struct AnalysisResult {
    string category, subcategory;
    double sentiment, confidence;
    string event_type, geo_region;
    vector<NerEntity> entities;
    vector<ExtractedDate> dates;
    SportsMatchData sports_data;
    vector<string> keywords;
    vector<string> semantic_tags;
    string summary;
};
```

---

## 5. Missing / Incomplete Signatures

| Function | Status | Notes |
|----------|--------|-------|
| `cluster_and_summarize` | **MISSING** | Called in Dart FFI but not in C++ header |
| `newsbrain_set_http_fetcher` | **UNUSED** | Dart doesn't set callback; uses Dart HTTP instead |
| `newsbrain_score_article_quality` | **UNBOUND** | Declared in C++, not bound in Dart |
| `yalla_model_manager_download` | **PARTIAL** | Needs callback trampoline implementation in Dart |

---

## 6. Memory Management Contract

| Allocator | Freed By | Owner |
|-----------|----------|-------|
| `process_url` | `free_string` | Caller |
| `analyze_article` | `free_string` | Caller |
| `cluster_articles_ex` | `free_cluster_string` | Caller |
| `validate_image_relevance` | `free_string` | Caller |
| `split_paragraphs_by_dots` | `free_string` | Caller |
| `clean_article_content` | `free_string` | Caller |
| `extract_story_elements` | `free_string` | Caller |
| `get_engine_logs` | `free_string` | Caller |
| `newsbrain_scan_url` | `newsbrain_free_string` | Caller |
| `newsbrain_scan_html` | `newsbrain_free_string` | Caller |
| `newsbrain_extract_article_url` | `newsbrain_free_string` | Caller |
| `newsbrain_extract_article_html` | `newsbrain_free_string` | Caller |
| `newsbrain_classify_article` | `newsbrain_free_string` | Caller |
| `newsbrain_classify_category` | `newsbrain_free_string` | Caller |
| `newsbrain_get_version` | `newsbrain_free_string` | Caller |
| `yalla_language_detector_normalize` | `yalla_free_string` | Caller |
| `yalla_entity_extractor_extract` | `yalla_entity_extractor_free_entities` | Caller |
| `yalla_event_clusterer_cluster` | `yalla_event_clusterer_free_clusters` | Caller |
| `yalla_model_manager_get_info` | `yalla_model_manager_free_info` | Caller |
| `yalla_model_manager_list_models` | `yalla_model_manager_free_list` | Caller |
| `yalla_summarizer_summarize` | `yalla_free_string` | Caller |
| `yalla_translator_translate` | `yalla_free_string` | Caller |
| `yalla_get_version` | `yalla_free_string` | Caller |
| `yalla_inference_engine_infer` (text/error) | `yalla_free_string` | Caller |

**Rule**: Every `const char*` returned from C++ MUST be freed by the corresponding free function.

---

## 7. JSON Schemas

### process_url Output
```json
{
  "success": true,
  "is_source": false,
  "title": "...",
  "summary": "...",
  "content": "...",
  "dot_split_content": ["...", "..."],
  "image_url": "...",
  "image_urls": ["..."],
  "category": "...",
  "sentiment": 0.5,
  "author": "",
  "publishDate": "",
  "keywords": ["...", "..."],
  "logs": "..."
}
```

### analyze_article Output
```json
{
  "category": "...",
  "subcategory": "...",
  "sentiment": 0.5,
  "confidence": 0.8,
  "event_type": "...",
  "geopolitical_region": "...",
  "keywords": ["..."],
  "semantic_tags": ["..."],
  "entities": [{"type": "...", "value": "...", "canonical": "...", "confidence": 0.9}],
  "dates": [{"raw": "...", "iso": "...", "confidence": 0.9}],
  "sports_data": {...}  // optional
}
```

### validate_image_relevance Output
```json
{
  "relevant": 1,
  "score": 0.75,
  "reasons": ["keyword_match:...", "title_match:..."]
}
```

### newsBrain PageSkeleton
```json
{
  "url": "...",
  "canonicalUrl": "...",
  "metadata": {"title": "...", "description": "...", "author": "...", ...},
  "nodes": [{"id": 0, "type": "ELEMENT", "tag": "div", "text": "...", ...}],
  "images": [{"src": "...", "alt": "...", "relevanceScore": 0.8, "isLead": true}],
  "candidates": [{"candidateId": 0, "rootNodeId": 5, "score": 0.9, "previewText": "..."}]
}
```

### newsBrain NewsArticle
```json
{
  "url": "...",
  "canonicalUrl": "...",
  "title": "...",
  "subtitle": "...",
  "author": "...",
  "publishDate": "...",
  "language": "...",
  "siteName": "...",
  "leadImageUrl": "...",
  "leadImageCaption": "...",
  "blocks": [{"type": "PARAGRAPH", "text": "..."}],
  "plainText": "...",
  "wordCount": 500,
  "readingTimeMinutes": 3,
  "confidenceScore": 0.85
}
```

---

## 8. Migration Checklist

- [ ] Add missing `cluster_and_summarize` to yalla_engine.h
- [ ] Bind `newsbrain_score_article_quality` in Dart
- [ ] Implement `newsbrain_set_http_fetcher` for Android (optional)
- [ ] Unify memory management (single free function?)
- [ ] Add version compatibility checks
- [ ] Document thread safety guarantees
- [ ] Add error codes to all functions
- [ ] Implement callback trampolines for async operations in Dart
- [ ] Test llama.cpp integration on Android (ARM64/ARM32)
- [ ] Verify GGUF model loading with Q4_K_M quantization