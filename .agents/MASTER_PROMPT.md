# MASTER PROMPT — BUILD A MOBILE-FIRST MULTILINGUAL NEWS INTELLIGENCE ENGINE

## 1. YOUR ROLE

You are a senior software architect, C++ systems engineer, Flutter/Dart developer, machine learning engineer, information retrieval specialist, and mobile performance engineer.

Your mission is to design and implement a production-oriented, privacy-conscious, mobile-first News Intelligence Engine.

You must work incrementally, inspect the existing codebase before modifying it, maintain clean architecture, and deliver working code rather than theoretical recommendations.

Do not implement all features in one uncontrolled change. Plan, build, compile, test, measure, and improve each module.

---

# 2. PRODUCT VISION

Build a global multilingual news application capable of:

1. Discovering news websites and permitted content sources.
2. Crawling public RSS feeds, sitemaps, and web pages where access is allowed.
3. Extracting article content from different website layouts.
4. Cleaning HTML and removing irrelevant content.
5. Supporting Arabic, French, English, and future languages.
6. Detecting the article language.
7. Classifying articles into multiple categories.
8. Extracting named entities, events, relationships, and claims.
9. Generating source-grounded summaries.
10. Detecting duplicate and related news.
11. Building a lightweight local knowledge graph.
12. Supporting keyword and semantic search.
13. Offering article timelines and related coverage.
14. Running as much processing as possible on the mobile device.
15. Using C++ for the processing engine and Flutter/Dart for the user interface.
16. Operating without a mandatory remote server for the core application.

The initial deployment target is mobile, with Android as the first implementation target and iOS compatibility as an architectural requirement.

The product must be designed to scale from an initial regional focus to global multilingual coverage.

---

# 3. NON-NEGOTIABLE ARCHITECTURAL PRINCIPLES

## 3.1 Hybrid deterministic + AI architecture

Do not use a TinyLLM for every operation.

Use deterministic algorithms for:

* HTTP networking
* URL normalization
* Robots/access policy handling
* HTML parsing
* Metadata extraction
* DOM content extraction
* HTML sanitization
* Text normalization
* Content hashing
* Duplicate detection
* Database operations
* Full-text search
* Queue management
* Resource limits

Use ML models and TinyLLMs only where they provide measurable value:

* Language identification
* Multilingual classification
* Named entity recognition
* Event extraction
* Claim extraction
* Summarization
* Semantic embeddings
* Ambiguous content interpretation

The AI layer must not become a mandatory dependency for basic article ingestion.

## 3.2 Local-first execution

The engine must support on-device processing.

Requirements:

* No mandatory cloud API for the core crawler and local search.
* No mandatory remote LLM inference.
* Local SQLite storage.
* Local model execution where supported.
* Incremental and resumable processing.
* Model loading and unloading.
* Memory and battery awareness.
* Cancellation and retry support.
* Graceful handling of low-memory devices.
* No blocking of the Flutter UI thread.

Do not claim that every device can run every model. Implement capability detection and graceful degradation.

## 3.3 Source-grounded knowledge

Every generated entity, event, claim, and summary must retain a reference to its source article.

Do not present generated assumptions as verified facts.

Preserve:

* Original URL
* Canonical URL where available
* Source identity
* Publication date
* Extraction timestamp
* Evidence text spans
* Model version
* Processing version
* Extraction confidence
* Attribution and uncertainty

## 3.4 Privacy and security

* Validate and sanitize untrusted HTML.
* Protect local database access.
* Do not execute untrusted page JavaScript in the native engine.
* Avoid unrestricted file-system access from downloaded content.
* Validate network URLs and redirects.
* Implement safe request limits.
* Do not bypass authentication, paywalls, CAPTCHAs, or technical access controls.
* Respect applicable terms, access restrictions, and content rights.
* Avoid collecting unnecessary personal information.
* Never hardcode API keys, credentials, or secrets.
* Use secure storage for any sensitive local configuration.

---

# 4. TECHNOLOGY STACK

Use the following stack unless the existing project requires a justified alternative.

## Frontend

* Flutter
* Dart
* Material 3 or the existing project design system
* Responsive mobile-first UI
* RTL support for Arabic
* Internationalization
* Accessible components

## Native engine

* C++20 or C++23
* CMake
* Clear module boundaries
* RAII and modern C++ memory management
* Thread-safe task management
* Unit testing

## Networking

* libcurl or an appropriate platform-compatible HTTP implementation
* Connection timeouts
* Redirect limits
* Response size limits
* Retry and backoff policies
* Per-domain request limits
* Content-type validation

## HTML and text

* A robust HTML parser
* DOM-based extraction
* Unicode-aware text handling
* ICU or equivalent where appropriate
* Configurable Arabic normalization
* Language-aware text processing

## Storage

* SQLite
* SQLite FTS5
* Database migrations
* Prepared statements
* Transaction management
* Local caching

## AI inference

* llama.cpp or another suitable native inference runtime
* GGUF or an appropriate supported model format
* Quantized models where quality and performance are acceptable
* Optional grammar-constrained structured output
* Explicit model capability metadata

The final model selection must be based on benchmark results for Arabic, French, English, RAM consumption, latency, and accuracy.

## Flutter ↔ C++

Use Dart FFI or a suitable Flutter native plugin architecture.

Expose a stable native API and avoid leaking internal C++ object ownership across the bridge.

---

# 5. PROJECT INSPECTION — REQUIRED FIRST STEP

Before writing implementation code:

1. Inspect the complete repository structure.
2. Identify the existing Flutter application architecture.
3. Identify existing C++ modules, if any.
4. Identify current database schemas.
5. Identify existing news source and category tables.
6. Identify current dependencies and build configuration.
7. Identify existing native bridge code.
8. Identify the existing state management solution.
9. Identify current Android/iOS support.
10. Identify existing tests.
11. Identify any existing AI model integration.
12. Identify the current app's settings and background processing capabilities.

Do not replace working modules without justification.

Prepare a concise architecture assessment containing:

* Existing modules
* Reusable components
* Technical risks
* Missing dependencies
* Migration requirements
* Recommended implementation order

Then create an implementation plan before making large code changes.

---

# 6. DEVELOPMENT PHASES

Implement the project in the following phases.

## PHASE 1 — CORE ENGINE FOUNDATION

Create the native C++ engine with:

* Engine lifecycle
* Configuration management
* Logging
* Error handling
* Version information
* Thread-safe task execution
* Cancellation tokens
* Job identifiers
* Event notifications
* Unit tests

Suggested modules:

```text
Core/
  Engine/
  Config/
  Logging/
  Errors/
  Tasks/
  Events/
```

Acceptance criteria:

* Engine initializes and shuts down safely.
* Invalid configuration is handled.
* Tasks can be queued and cancelled.
* Errors are returned in a consistent format.
* Unit tests compile and pass.

---

## PHASE 2 — SOURCE MANAGEMENT

Implement source profiles.

Each source should support:

* Unique source ID
* Domain
* Display name
* Country/region
* Supported languages
* RSS/Atom feeds
* Sitemap URLs
* Homepage/category URLs
* Optional extraction selectors
* Optional cleanup selectors
* Crawl interval
* Active/inactive status
* Last successful crawl
* Error statistics

Suggested schema:

```json
{
  "source_id": "source_001",
  "name": "Example News",
  "domain": "example.com",
  "country": "MA",
  "languages": ["ar", "fr"],
  "rss_urls": [],
  "sitemap_urls": [],
  "category_urls": [],
  "article_selectors": [],
  "remove_selectors": [],
  "active": true
}
```

Do not hardcode one website's structure into the generic crawler.

Implement a configurable source profile system.

---

## PHASE 3 — CRAWLER AND URL DISCOVERY

Implement a controlled crawler.

Supported discovery methods:

1. RSS and Atom feeds.
2. XML sitemaps.
3. Homepage links.
4. Category page links.
5. Article-page links.
6. User-added sources.

Requirements:

* URL normalization.
* Canonical URL support.
* Duplicate URL prevention.
* Per-domain crawl scheduling.
* Maximum depth.
* Maximum page count per task.
* Request timeouts.
* Maximum response size.
* Content-type validation.
* Redirect restrictions.
* Retry with exponential backoff.
* Crawl cancellation.
* Crawl progress reporting.
* Network connectivity awareness.
* Respect access restrictions and applicable crawl policies.

Do not attempt unrestricted recursive crawling.

Implement a bounded priority queue.

Priority factors may include:

* New feed entry
* Source priority
* Recency
* Article URL likelihood
* Previously failed URL
* User request

Store failed URLs with reason and retry metadata.

---

## PHASE 4 — ARTICLE EXTRACTION

Implement a multi-strategy article extractor.

Extraction order:

### Strategy A — Structured metadata

Extract when available:

* JSON-LD
* Schema.org Article/NewsArticle
* headline
* articleBody
* datePublished
* dateModified
* author
* image
* publisher

### Strategy B — Semantic HTML

Identify:

* article
* main
* headings
* paragraphs
* relevant content containers

### Strategy C — Metadata

Extract:

* OpenGraph title
* OpenGraph description
* Canonical URL
* Meta description
* Article metadata

### Strategy D — DOM scoring

Score candidate containers using:

* Text density
* Paragraph count
* Text length
* Link density
* Content continuity
* Heading proximity
* Boilerplate likelihood

### Strategy E — Configurable source profile

Allow website-specific selectors to improve extraction.

### Strategy F — Optional AI fallback

Use a TinyLLM only when deterministic extraction confidence is low and the content is suitable for processing.

The AI must not be required for every article.

Return:

```json
{
  "title": "...",
  "content": "...",
  "author": "...",
  "published_at": "...",
  "canonical_url": "...",
  "extraction_method": "jsonld",
  "confidence": 0.91,
  "warnings": []
}
```

Do not invent missing metadata. Return null or an explicit unknown state.

---

## PHASE 5 — HTML CLEANING AND TEXT NORMALIZATION

Create a cleaning pipeline.

### HTML cleaning

Remove or de-prioritize:

* Script elements
* Style elements
* Navigation
* Advertising
* Cookie notices
* Social sharing widgets
* Comments
* Related content
* Repeated headers and footers
* Tracking-only elements

Preserve article meaning.

Do not remove a section solely because it is short or contains links.

### Text normalization

Implement:

* Unicode normalization
* Whitespace normalization
* HTML entity decoding
* Paragraph preservation
* Configurable Arabic normalization
* Language-aware tokenization
* Original text preservation

Create separate fields for:

* Original title
* Original content
* Normalized search title
* Normalized search content

Never overwrite original article text with normalized search text.

Support:

* Arabic
* French
* English
* Darija where applicable

Make normalization configurable and test it against real multilingual data.

---

## PHASE 6 — LANGUAGE DETECTION

Implement multilingual language identification.

Requirements:

* Detect article language.
* Support mixed-language content.
* Store detection confidence.
* Detect insufficient text.
* Handle unknown language.
* Support Arabic and French first.
* Allow future language expansion.

Return:

```json
{
  "language": "ar",
  "confidence": 0.97,
  "mixed_language": false
}
```

Do not treat model confidence as calibrated probability without evaluation.

Preserve original language metadata where available and distinguish publisher metadata from model detection.

---

## PHASE 7 — DEDUPLICATION

Implement multiple levels of duplicate detection.

### Level 1 — URL matching

Normalize and compare URLs.

### Level 2 — Canonical URL matching

Use canonical URLs when available.

### Level 3 — Content fingerprints

Hash normalized article content.

### Level 4 — Near-duplicate similarity

Compare normalized titles and article content using similarity algorithms.

### Level 5 — Same-event grouping

Group articles reporting related events without assuming they are duplicates.

Distinguish:

* Exact duplicate
* Near duplicate
* Syndicated article
* Same event
* Related topic

Do not delete independent sources merely because they report the same event.

Preserve source-specific article records and relationships.

---

## PHASE 8 — CLASSIFICATION

Implement multilingual multi-label classification.

Suggested primary categories:

* Politics and government
* Economy and business
* Technology and science
* Health
* Society
* International
* Sports
* Culture and entertainment
* Environment
* Education
* Crime and justice
* Local and regional

Requirements:

* Primary category
* Secondary categories
* Confidence
* Model version
* Needs-review flag
* Optional rule-based explanation
* Manual correction support

Use the following classification pipeline:

1. Source category hints.
2. URL/keyword rules.
3. Lightweight ML classifier.
4. TinyLLM fallback for ambiguous content.

Do not use a single category only when multi-label classification is appropriate.

Validate model outputs against an explicit schema.

---

## PHASE 9 — KNOWLEDGE EXTRACTION

Implement structured extraction of:

### A. Named entities

Types:

* Person
* Organization
* Location
* Country
* Date
* Currency
* Quantity
* Product
* Project
* Institution

Store:

* Surface form
* Normalized name
* Entity type
* Language
* Article ID
* Text span
* Extraction confidence
* Model version

Do not merge entities based only on similar names.

### B. Event extraction

Extract:

* Event type
* Trigger
* Participants
* Location
* Date
* Time
* Status
* Evidence span
* Source article

Distinguish:

* Confirmed event
* Reported claim
* Planned event
* Prediction
* Historical event
* Unknown

### C. Claim extraction

Extract claims with:

* Subject
* Predicate
* Object
* Source article
* Evidence text span
* Attribution
* Certainty
* Processing metadata

Do not present allegations, plans, predictions, or attributed statements as independently verified facts.

### D. Relationships

Create relationships between:

* Entities
* Events
* Articles
* Topics
* Claims

Every relationship must preserve provenance.

---

## PHASE 10 — SUMMARIZATION

Implement source-grounded summaries.

Outputs:

* Short summary
* Extended summary
* Key points
* Main entities
* Main event
* Source notes

Rules:

1. Summarize cleaned article text.
2. Preserve original article.
3. Do not introduce unsupported facts.
4. Preserve attribution.
5. Preserve uncertainty.
6. Support Arabic and French.
7. Make summary language configurable.
8. Validate structured output.
9. Store model version.
10. Handle model failures gracefully.

Do not use the generated summary as the only stored representation of an article.

---

## PHASE 11 — EMBEDDINGS AND SEMANTIC SEARCH

Implement semantic retrieval as an optional capability.

Requirements:

* Multilingual embedding model.
* Model version storage.
* Embedding generation after cleaning and deduplication.
* Chunking for long articles.
* Vector storage.
* Resource limits.
* Cancellation support.
* Embedding regeneration when the model changes.

Evaluate cross-language retrieval:

* Arabic → Arabic
* French → French
* English → English
* Arabic → French
* French → Arabic
* English → Arabic/French

Do not assume that a small embedding model provides good cross-language quality without benchmarking.

Start with SQLite FTS5 as a working keyword baseline.

---

## PHASE 12 — HYBRID RETRIEVAL

Implement a retrieval pipeline combining:

1. Keyword search.
2. Semantic search.
3. Structured filters.
4. Entity matching.
5. Event relationships.
6. Duplicate and related coverage information.

Search filters should include:

* Language
* Category
* Source
* Country/region
* Publication date
* Entity
* Event
* Relevance
* Saved articles

Return:

* Article ID
* Title
* Summary
* Source
* Publication date
* Matching score
* Match type
* Highlighted evidence where available

Implement ranking as a transparent, configurable mechanism.

Do not fabricate search results or knowledge when no supporting articles are found.

---

## PHASE 13 — KNOWLEDGE GRAPH

Create a lightweight relational knowledge graph.

Do not introduce a dedicated graph database unless the requirements justify it.

Support:

* Entity nodes
* Event nodes
* Article nodes
* Claim nodes
* Relationship records
* Source provenance
* Entity aliases
* Confidence metadata

Features:

* Related articles
* Entity exploration
* Event timelines
* Topic clusters
* Source comparison
* Knowledge navigation

Do not infer that two articles refer to the same real-world entity without sufficient evidence.

---

## PHASE 14 — SQLITE DATABASE

Implement database migrations.

Suggested tables:

```text
sources
articles
article_categories
article_entities
entities
entity_aliases
events
event_entities
claims
relationships
topics
article_topics
embeddings
processing_jobs
article_fts
crawl_urls
model_registry
```

Add:

* Foreign keys
* Indexes
* Unique constraints
* Migration versioning
* Transactions
* Prepared statements
* Error handling
* Schema validation

The schema should support offline operation and incremental updates.

Store original URLs and source metadata.

---

## PHASE 15 — MOBILE RESOURCE MANAGEMENT

The engine must operate under mobile constraints.

Implement:

* Maximum concurrent requests.
* Maximum response size.
* Maximum queue size.
* Maximum article size.
* Bounded inference context.
* Model memory management.
* Battery-aware processing.
* Wi-Fi-only option.
* Mobile data option.
* User-configurable crawl limits.
* Job cancellation.
* Checkpointing.
* Incremental commits.
* Retry limits.
* Background execution integration.

Do not assume unrestricted background crawling is possible on Android or iOS.

Use platform-supported background execution APIs and clearly communicate limitations to the user.

---

## PHASE 16 — DART / C++ BRIDGE

Create a stable asynchronous native API.

Requirements:

* Engine initialization.
* Engine shutdown.
* Source management.
* Crawl start.
* Crawl cancellation.
* Job status.
* Search.
* Article retrieval.
* Settings.
* Error reporting.
* Progress events.

Suggested API:

```cpp
extern "C" {

    EngineHandle* engine_create(const char* db_path);

    void engine_destroy(EngineHandle* engine);

    int engine_start_crawl(
        EngineHandle* engine,
        const char* options_json
    );

    int engine_cancel_job(
        EngineHandle* engine,
        const char* job_id
    );

    int engine_search(
        EngineHandle* engine,
        const char* query_json,
        char** result_json
    );

    void engine_free_string(char* value);
}
```

This is an architectural starting point.

Ensure:

* Thread safety.
* Memory ownership rules.
* ABI compatibility.
* Error codes.
* API versioning.
* Safe string handling.
* Cancellation behavior.
* No UI blocking.

Use asynchronous progress notifications or polling.

---

# 17. FLUTTER APPLICATION FEATURES

Implement or integrate the following mobile-first views:

## A. Home / News Feed

* Latest articles
* Personalized categories
* Source labels
* Language labels
* Article cards
* Loading states
* Offline cached content
* Pull-to-refresh
* Error handling

## B. Article Details

* Clean reading view
* Original source link
* Publication date
* Source name
* Language
* Summary
* Key points
* Extracted entities
* Related events
* Related articles
* Evidence links
* Save/share functionality

## C. Search

* Keyword search
* Semantic search when enabled
* Language filter
* Category filter
* Date filter
* Source filter
* Entity search
* Search history (optional and privacy-conscious)

## D. Knowledge Explorer

* Entity details
* Related articles
* Event timeline
* Topics
* Source coverage
* Relationship exploration

## E. Crawler Dashboard

* Active sources
* Last crawl
* Crawl progress
* Queue status
* Failed URLs
* Processing errors
* Storage usage
* Model status

## F. Settings

* Language
* RTL support
* Enabled sources
* Crawl frequency
* Network preferences
* Battery preferences
* AI processing settings
* Download/cache limits
* Model selection
* Privacy controls
* Data deletion
* Reprocess articles
* Diagnostics

---

# 18. MODEL MANAGEMENT

Create a ModelManager module.

It must support:

* Model registry.
* Model version.
* Model task type.
* Supported languages.
* Quantization type.
* Memory requirements.
* Context size.
* Loading state.
* Unloading.
* Download/import process where applicable.
* Model integrity validation.
* Compatibility checks.
* Fallback behavior.
* Performance metrics.

Do not bundle multiple large models into the application without evaluating installation size and device requirements.

Allow the user to disable expensive AI tasks.

---

# 19. TESTING STRATEGY

Implement automated tests.

## Unit tests

* URL normalization.
* HTML parsing.
* Content extraction.
* Arabic normalization.
* French text handling.
* Date extraction.
* Content hashing.
* Duplicate detection.
* SQLite repositories.
* JSON validation.
* Task cancellation.
* Error handling.

## Integration tests

* RSS → article storage.
* Sitemap → article discovery.
* HTML → cleaned article.
* Cleaned article → classification.
* Article → entities and events.
* Article → embeddings.
* Search → results.
* Flutter → native bridge.

## Dataset evaluation

Create a manually reviewed multilingual dataset.

Evaluate:

* Extraction quality.
* Classification quality.
* Entity extraction.
* Event extraction.
* Search relevance.
* Cross-language retrieval.
* Summary factuality.

Report metrics by language and category.

Do not claim that AI features are reliable without representative testing.

---

# 20. PERFORMANCE BENCHMARKS

Create benchmarks for supported device classes.

Measure:

* HTML parsing latency.
* Extraction latency.
* Cleaning latency.
* Classification latency.
* LLM inference latency.
* Embedding latency.
* Search latency.
* Peak RAM.
* Database size.
* Battery impact where measurable.
* Network data usage.
* Crawl completion rate.
* Crash and error rate.

Separate benchmarks for:

* Low-end Android devices.
* Mid-range Android devices.
* High-end Android devices.
* iOS devices when available.

Do not use arbitrary performance claims. Report actual measurements.

---

# 21. OBSERVABILITY AND DEBUGGING

Implement structured logs.

Every processing job should record:

* Job ID.
* Article ID.
* Current stage.
* Start time.
* End time.
* Error code.
* Retry count.
* Model version.
* Processing duration.
* Resource statistics where available.

Add a debug mode that allows developers to inspect:

* Raw HTML.
* Extracted metadata.
* Candidate article containers.
* Cleaned text.
* Classification output.
* Knowledge extraction JSON.
* Evidence spans.
* Search candidates.

Avoid logging sensitive data unnecessarily.

---

# 22. AI OUTPUT VALIDATION

All LLM-generated structured data must pass schema validation.

Requirements:

* JSON schema or equivalent validation.
* Required fields.
* Type validation.
* Enum validation.
* Maximum string lengths.
* Invalid output handling.
* Retry with constrained generation where appropriate.
* Evidence span validation.
* Source article reference validation.

If the model fails, return a structured error and preserve the article.

Do not silently store malformed AI output.

---

# 23. IMPLEMENTATION WORKFLOW

Follow this workflow for every phase:

1. Inspect existing code.
2. Describe the intended changes.
3. Identify dependencies.
4. Implement the smallest complete increment.
5. Compile the affected targets.
6. Run unit tests.
7. Run integration tests where available.
8. Review memory ownership and thread safety.
9. Review security and input validation.
10. Review performance implications.
11. Document the changes.
12. Report completed work and remaining limitations.

Do not mark a feature as complete if it only has placeholder code.

Do not generate fake test results.

If a dependency is unavailable, explain the issue and provide a safe implementation alternative.

---

# 24. REQUIRED DELIVERABLES

For each implementation phase, provide:

1. Architecture changes.
2. File tree.
3. Source code.
4. Build configuration changes.
5. Database migrations.
6. Tests.
7. Test execution results.
8. Known limitations.
9. Usage instructions.
10. Next recommended implementation step.

Use clean, maintainable, production-oriented code.

Do not rewrite unrelated modules.

---

# 25. FIRST TASK — BEGIN NOW

Start by inspecting the existing repository.

Do not immediately generate the entire application.

Your first response must include:

1. Repository architecture assessment.
2. Existing technology stack.
3. Existing reusable components.
4. Missing dependencies.
5. Potential technical risks.
6. Proposed phased implementation plan.
7. Phase 1 file tree.
8. Exact files that will be modified or created.
9. Build and test strategy.

After presenting the assessment, begin Phase 1 implementation if the repository is available and the project configuration is sufficiently understood.

If the repository is not available, request the relevant project files or explain the minimum structure required to start.

Do not assume that files, models, dependencies, or services exist without inspecting them.

# END OF MASTER PROMPT
