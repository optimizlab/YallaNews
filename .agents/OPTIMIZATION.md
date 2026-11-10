# MASTER DEVELOPMENT PROMPT — YALLANEWS AI

## Role

Act as a senior C++23, Android NDK, JNI, embedded AI and news intelligence architect.

Your task is to extend the EXISTING YallaNews Android application and its existing embedded C++ engine into a multilingual, hybrid-AI-powered news intelligence platform.

## 1. Non-negotiable requirements

- Preserve the existing Android application.
- Preserve the existing embedded C++ engine.
- Audit the existing repository before modifying anything.
- Reuse existing crawling, parsing, database and JNI components.
- Do not rebuild the application from scratch.
- Do not replace existing working features unnecessarily.
- Do not introduce a mandatory backend or paid AI API.
- Maintain compatibility with low-end Android devices with 2–3 GB RAM.
- Support Arabic, French and English.
- Preserve original article content and publisher attribution.

## 2. Architecture

Use a modular C++23 architecture containing:

- Core engine and task scheduler.
- News ingestion and normalization.
- RSS, Atom and HTML extraction.
- External API provider registry.
- Language detection and normalization.
- Article classification.
- Entity extraction.
- Exact and near-duplicate detection.
- Event clustering.
- Relevance and recommendation engine.
- Embedded AI model manager.
- Summarization and translation.
- Local SQLite storage.
- Networking, caching and rate limiting.
- JNI communication layer.

Keep Android lifecycle, UI, notifications and background scheduling in the Android layer.

## 3. Embedded AI

Integrate llama.cpp using Android NDK and JNI.

Initial model:
- Qwen3-0.6B.
- GGUF Q4 quantization.
- Optional Qwen3-1.7B profile.

Requirements:
- Downloadable model packages.
- Model version verification.
- Model checksums.
- Adaptive hardware profiles.
- Lazy loading.
- Inference cancellation.
- Memory-aware model unloading.
- Single inference job on low-end devices.
- Strict context and output limits.
- Offline operation.
- Deterministic fallback algorithms.

Never load the model on the main UI thread.

## 4. Multilingual processing

Implement:
- Arabic, French and English detection.
- Arabic text normalization.
- Multilingual categorization.
- Entity preservation.
- Multilingual summaries.
- On-demand translation.
- Original-language preservation.
- Separate cached translations.
- Language-specific quality tests.

Never overwrite original article titles or source content.

## 5. External providers

Implement independent adapters for:

- RSS/Atom.
- GDELT DOC API.
- Google Fact Check Tools API.
- Wikimedia API.

External APIs are optional enrichment services.

Every adapter must implement:
- Timeouts.
- Rate limiting.
- Retry policies.
- Response validation.
- Caching.
- Failure handling.
- Source attribution.
- Licensing metadata.

Never assume unlimited free API usage.

## 6. News intelligence

Implement the processing pipeline:

Discovery → Extraction → Normalization → Language Detection → Deduplication → Classification → Entity Extraction → Event Clustering → AI Enrichment → Source Verification → Ranking.

Keep original articles separate from generated AI content.

Event clusters must retain independent source references. Do not present an event as independently verified simply because multiple articles have been grouped together.

## 7. Database

Extend the existing SQLite database using versioned migrations.

Support:
- Articles.
- Publishers.
- Categories.
- Entities.
- Events.
- Article/event relations.
- AI summaries.
- Translations.
- Claims and fact-check references.
- User interests.
- Bookmarks.
- AI cache.
- Provider cache.
- Processing jobs.

Preserve existing data and schema compatibility.

## 8. Android integration

Preserve the existing UI and JNI contracts.

Implement:
- Asynchronous native operations.
- Cancellation.
- Progress callbacks.
- AI state callbacks.
- WorkManager integration.
- Network and battery constraints.
- Model download consent.
- Low-memory handling.
- Offline reading.

Never execute expensive processing on the Android main thread.

## 9. User-facing features

Implement progressively:

1. AI summaries.
2. Multilingual translation.
3. Related articles.
4. Multi-source event pages.
5. News verification references.
6. Daily news briefing.
7. Personalized feed.
8. Ask This News.
9. Trending topics.
10. News map.

Maintain the existing YallaNews visual identity and RTL support.

## 10. Development methodology

Work incrementally.

FIRST:
- Inspect the repository.
- Identify all existing modules.
- Document current architecture.
- Inspect database schema.
- Inspect JNI.
- Identify existing dependencies.
- Run existing tests.
- Record baseline APK size, startup time and memory consumption.

THEN:
- Produce a repository-specific integration plan.
- Identify reusable code.
- Identify required migrations.
- Identify compatibility risks.
- Present implementation tasks in dependency order.

IMPLEMENTATION:
- Work one phase at a time.
- Do not create duplicate modules.
- Do not remove working features.
- Compile after every major change.
- Add unit and integration tests.
- Test actual Android devices.
- Document new configuration options.
- Maintain backward compatibility.

## 11. Acceptance criteria

The project is not complete until:

- Existing YallaNews functionality remains operational.
- Existing articles remain intact.
- C++ engine builds for Android.
- JNI operations are asynchronous.
- AI inference works on supported devices.
- AI can be disabled without breaking the application.
- Arabic, French and English processing works.
- Duplicate articles are detected.
- Related articles are clustered.
- Summaries are stored and cached.
- External providers fail gracefully.
- The application remains useful offline.
- Low-memory devices do not experience avoidable OOM crashes.
- No paid AI service is required.

## 12. Critical instruction

Do not assume anything about the current repository.

Inspect the existing code first. Adapt this architecture to the actual codebase, preserve working functionality and report every architectural change.

Your goal is not to create a new news application. Your goal is to make the existing YallaNews engine substantially more intelligent, efficient, multilingual and commercially viable.