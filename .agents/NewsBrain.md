# NewsBrain
## Production Architecture & Implementation Specification

**Project:** NewsBrain  
**Platform:** Android first, then iOS, Windows and Linux  
**Implementation:** C++17 minimum; C++20 recommended  
**Interface:** Stable C ABI + native C++ API  
**Intelligence:** Hybrid deterministic + optional generative model  
**Working memory:** 16 MiB maximum for the native core  
**Memory lifecycle:** Temporary, isolated per processing job  
**Primary languages:** Arabic, French and English  
**Primary purpose:** Understand news information and independently write original, professionally structured news articles.

---

# 1. Product definition

NewsBrain is a compact news intelligence and editorial writing engine.

It is not simply:
- An HTML parser.
- A news cleaner.
- A summarizer.
- A keyword extractor.
- A sentence paraphraser.
- A generic AI wrapper.

It must behave like a news editorial writer.

Given a news item and its available information, the engine must:

1. Read and interpret the material.
2. Identify what happened.
3. Identify the people, organizations, places, dates and figures involved.
4. Distinguish facts, claims, opinions and allegations.
5. Understand the relationship between the information.
6. Determine the main editorial angle.
7. Organize the important facts into a new narrative.
8. Write a new article in the requested language.
9. Verify the resulting article against its evidence.
10. Return the article with its provenance and quality diagnostics.

The output must be a new editorial composition, not a cleaned source article.

# 2. Non-negotiable design principles

- Mobile-first, CPU-first and allocation-conscious.
- The core must operate without a generative model.
- No mandatory cloud API.
- No mandatory `llama.cpp` dependency.
- No persistent article memory.
- No global article cache.
- No hidden retention of source text between jobs.
- No invented facts, quotations, dates, numbers or sources.
- No automatic publication of unsupported articles.
- No sentence-by-sentence paraphrasing.
- No copying of source paragraph order as the default writing strategy.
- No unbounded memory allocation.
- No blocking of the mobile UI thread.
- Every processing operation must support cancellation.
- Every result must carry its provenance and validation status.

# 3. Architecture

Use a layered architecture.

```text
                    HOST APPLICATION
                 Android / iOS / Desktop
                           |
                     Stable C ABI
                           |
                 NewsBrain CORE
                           |
       +-------------------+-------------------+
       |                   |                   |
   INPUT LAYER        INTELLIGENCE LAYER   EDITORIAL LAYER
       |                   |                   |
  Text Adapter         Language Engine      Story Engine
  HTML Adapter         Fact Engine           Editorial Planner
  RSS Adapter          Entity Engine         News Writer
  Plain Text           Event Understanding   Rewrite Engine
  Metadata Adapter     Claim Detection       Article Composer
       |                   |                   |
       +-------------------+-------------------+
                           |
                    VALIDATION LAYER
                           |
                Fact Guard / Similarity Guard
                 Editorial Quality / Provenance
                           |
                    STRUCTURED OUTPUT
```

Optional intelligence backends:

```text
              GENERATION BACKEND INTERFACE
                           |
              +------------+------------+
              |            |            |
          Deterministic  Remote       Local
          Writer         Model        Model
                         Adapter      Adapter
```

The core must never depend on any specific generation backend.

# 4. Core modules

## 4.1 InputAdapter

Purpose: accept content from different sources without requiring the host to provide perfectly cleaned text.

Supported input:
- Raw article text.
- HTML source.
- Extracted webpage text.
- RSS/Atom article data.
- Title and description.
- User-provided content.
- Multiple related source items.

Responsibilities:
- UTF-8 validation.
- Unicode normalization.
- HTML entity decoding.
- Removal of obvious navigation, scripts and markup noise.
- Detection of repeated text blocks.
- Paragraph segmentation.
- Extraction of title, body, metadata and links where available.
- Preservation of original source text for the duration of the job.
- Input-size enforcement.

Do not build a full browser engine into the library. The host can provide rendered or extracted text when JavaScript rendering is required.

Input must retain two separate representations:

1. `raw_content`: original supplied content.
2. `normalized_content`: normalized working text.

Never overwrite the original with normalized text.

## 4.2 LanguageEngine

Responsibilities:
- Detect Arabic, French and English.
- Detect mixed-language content.
- Identify the dominant language.
- Identify the language of individual paragraphs when useful.
- Normalize Arabic character variants for matching.
- Normalize whitespace and punctuation.
- Preserve original text separately.
- Support transliteration only as an optional matching aid.

Arabic normalization must not destroy meaningful distinctions in the original article.

The engine must distinguish:
- Original Arabic text.
- Normalized Arabic text.
- Transliteration.
- Translated text.

Do not automatically translate the input before understanding it. Translation can lose names, political nuance, legal wording and other important distinctions.

## 4.3 ContentUnderstandingEngine

This is the first major intelligence module.

Its job is to determine what the news item actually communicates.

Extract:
- Main event.
- Secondary events.
- Actors.
- Organizations.
- Locations.
- Dates and times.
- Quantities and figures.
- Statements.
- Actions.
- Causes explicitly stated.
- Consequences explicitly stated.
- Claims and allegations.
- Opinions.
- Uncertainties.
- Missing information.

It should produce structured representations rather than immediately generating prose.

Example:

```json
{
  "main_event": "A new public transport project was announced",
  "actors": [
    {
      "name": "Example Municipality",
      "type": "organization"
    }
  ],
  "facts": [
    {
      "id": "F001",
      "subject": "Example Municipality",
      "predicate": "announced",
      "object": "a transport project",
      "evidence": ["S001:P003"],
      "confidence": 0.95
    }
  ],
  "unknowns": [
    "The announcement does not specify the completion date"
  ]
}
```

This is an illustrative structure, not a claim that the confidence score is already calibrated.

## 4.4 FactEngine

The FactEngine is the foundation of reliable article writing.

Each extracted fact must have:
- Unique job-local identifier.
- Subject.
- Predicate or relationship.
- Object or value.
- Fact type.
- Source identifier.
- Supporting passage or character offsets.
- Original language.
- Extraction method.
- Confidence.
- Verification state.

Recommended fact types:

- Confirmed by supplied source.
- Attributed statement.
- Allegation.
- Opinion.
- Estimate.
- Historical context.
- Unverified claim.
- Unknown or missing.

The engine must not convert an allegation into an established fact.

For example:

Source: "The company is accused of violating the agreement."

Incorrect output: "The company violated the agreement."

Correct output: "The company faces accusations of violating the agreement."

The engine must preserve this distinction through every editorial stage.

## 4.5 EntityEngine

Identify and normalize:
- People.
- Organizations.
- Companies.
- Government institutions.
- Countries.
- Cities.
- Geographic locations.
- Political institutions.
- Sports clubs.
- Competitions.
- Products and projects.

Entity records must preserve original spellings and canonical forms.

Arabic, French and English names must not be merged merely because their spellings look similar.

## 4.6 EventUnderstandingEngine

Determine whether the input describes:
- A new event.
- An update to an existing event.
- A reaction to an event.
- A historical event.
- An opinion about an event.
- Several unrelated events.

Build a temporary event representation.

The event representation is used to organize the current job only. It is discarded after the job completes.

## 4.7 SourceEvidenceEngine

Every source must receive a temporary source identifier.

Evidence records must reference:
- Source identifier.
- URL, if supplied.
- Publisher, if supplied.
- Publication date, if supplied.
- Extracted passage.
- Passage offsets.
- Source language.
- Attribution information.

Do not claim that multiple sources independently confirm a fact if they reproduce the same press release or syndicated material.

If source independence cannot be established, mark it as unknown.

# 5. Editorial intelligence

## 5.1 StoryEngine

The StoryEngine determines the story behind the information.

It must answer internally:

- What is the main news?
- Why is it newsworthy?
- Who is directly affected?
- What is the most important development?
- What information is essential?
- What information is secondary?
- What context is necessary?
- What is not established?
- What should not be included?

The StoryEngine must not invent motivations, implications or consequences.

## 5.2 EditorialPlanner

This module makes the editorial decisions before writing.

It generates an editorial plan with:

- Article type.
- Editorial angle.
- Main message.
- Target audience.
- Target language.
- Headline direction.
- Introduction objective.
- Body section plan.
- Supporting facts for each section.
- Necessary attributions.
- Uncertainties to communicate.
- Conclusion objective.
- Target length.

Possible article types:

- Breaking news.
- General news.
- Government announcement.
- Economy.
- Business.
- Politics.
- International affairs.
- Technology.
- Sports.
- Culture.
- Health information.
- Interview-based news.
- Event report.
- Follow-up report.

The selected article type must influence the structure and writing style.

## 5.3 NewsWriter

This is the most important product module.

It must behave as an independent professional news writer.

The writer receives:
- Editorial plan.
- Structured facts.
- Evidence references.
- Entity information.
- Event information.
- Requested language.
- Requested article length.
- Editorial style.

It must not receive an instruction to simply replace words in the original source.

### Writing process

**Stage A — Choose the angle**

Identify the most newsworthy and supportable aspect of the event.

**Stage B — Create a new structure**

Build a new article outline independently of the source paragraph sequence.

**Stage C — Write the headline**

Create a clear, informative and accurate headline.

Avoid sensationalism and unsupported claims.

**Stage D — Write the introduction**

The first paragraph should communicate the central development and its most important supported information.

**Stage E — Develop the article**

Organize facts in a coherent order. Explain relevant context, identify actors, describe developments and preserve attribution.

**Stage F — Write the conclusion**

Close with a relevant next step, confirmed consequence, official position or unresolved question when supported by the information.

Never invent a forward-looking conclusion.

### Originality rules

The writer must:
- Generate a new narrative structure.
- Produce independently composed sentences.
- Avoid retaining distinctive source phrases.
- Avoid copying source paragraph order.
- Avoid copying a source headline with superficial substitutions.
- Preserve proper names, official titles and necessary technical terminology.
- Preserve direct quotations only when they are supplied, attributable and intentionally retained.
- Never fabricate quotations.

Originality is not achieved by replacing words with synonyms. It comes from independently organizing and expressing the supported information.

## 5.4 GenerationBackend

Define a backend interface:

```cpp
class IGenerationBackend {
public:
    virtual ~IGenerationBackend() = default;

    virtual GenerationResult generate(
        const EditorialPlan& plan,
        const FactSheet& facts,
        const GenerationOptions& options,
        CancellationToken& cancellation
    ) = 0;

    virtual BackendCapabilities capabilities() const = 0;
};
```

Implement three backends.

### A. DeterministicWriter

Runs inside the strict 16 MiB core.

Uses:
- Fact ordering.
- Editorial templates.
- Language-specific sentence construction.
- Rule-based transitions.
- Attribution templates.
- Paragraph planning.
- Controlled vocabulary.

This provides a functional fallback, not a claim of human-level creative writing.

### B. RemoteGenerationBackend

Optional adapter for a model hosted outside the device.

The host application controls networking, credentials and privacy policy.

Send only the structured information required for generation. Do not send the complete original source unless explicitly necessary and authorized.

The backend must support:
- Timeout.
- Cancellation.
- Response-size limits.
- Retry policy.
- Structured response validation.
- No automatic publication of invalid responses.

### C. LocalGenerationBackend

Optional separately budgeted model integration.

`llama.cpp` may be integrated through this backend, but it must not be linked as a mandatory dependency of the core.

The local backend must declare:
- Model file size.
- Peak resident memory.
- Context memory.
- Inference workspace.
- Supported languages.
- Maximum output length.
- Hardware requirements.

A model exceeding the active device budget must be rejected before loading.

The 16 MiB profile must not load this backend.

# 6. Article validation

## 6.1 FactGuard

Check every factual statement in the generated article.

For each statement, determine:
- Is there supporting evidence?
- Is the statement attributed correctly?
- Does it change the meaning of the source?
- Does it introduce an unsupported number, date or name?
- Does it convert a claim into a fact?
- Does it imply causality that was never established?
- Does it overstate certainty?

Statements without adequate evidence must be removed, rewritten with proper qualification, or flagged.

## 6.2 SimilarityGuard

Compare the generated article with the supplied source material.

Use lightweight methods:
- Normalized exact phrase detection.
- Token n-gram overlap.
- Sentence-level similarity.
- Repeated distinctive phrase detection.
- Headline similarity.
- Paragraph structure comparison.

Arabic matching must account for normalization, but normalization must not cause unrelated expressions to be treated as identical.

Similarity thresholds must be configurable and evaluated against real editorial examples.

A similarity score is a warning signal, not proof of plagiarism or originality.

## 6.3 EditorialQualityEngine

Evaluate:
- Clarity.
- Coherence.
- Grammar.
- Readability.
- Headline accuracy.
- Introduction quality.
- Repetition.
- Paragraph structure.
- Attribution.
- Language consistency.
- Completeness.
- Unsupported statements.

Scores must be tied to documented tests and evaluation methods. Do not generate arbitrary percentages and present them as objective quality measurements.

## 6.4 EditorialDecision

Return one of:

- `READY`: sufficient evidence and acceptable validation.
- `READY_WITH_WARNINGS`: article is usable with disclosed limitations.
- `NEEDS_REVIEW`: editorial or factual issues require human review.
- `REJECTED`: insufficient or contradictory information.

Never force a publication-ready article from inadequate source information.

# 7. Temporary memory design

Memory is strictly job-scoped.

```text
Job starts
    |
    v
Create isolated JobContext
    |
    v
Allocate bounded working buffers
    |
    v
Process input and facts
    |
    v
Generate and validate article
    |
    v
Serialize result
    |
    v
Destroy JobContext
    |
    v
Release all temporary memory
```

No article memory persists between independent jobs.

Do not implement:
- Persistent vector database.
- Persistent event graph.
- Permanent article cache.
- Automatic learning from previously processed articles.
- Global history of source content.

Within a job, retain only what is needed for the current article.

If several sources are supplied together, their facts and evidence may be shared inside that job.

# 8. Memory budget

The 16 MiB budget is a hard native-core working-memory ceiling.

Suggested allocation:

| Component | Budget |
|---|---:|
| Core runtime and configuration | 1.0 MiB |
| Input and normalized text | 3.0 MiB |
| Tokenization and language processing | 1.5 MiB |
| Facts, entities and evidence | 2.0 MiB |
| Editorial plan and story representation | 1.0 MiB |
| Generation request and response buffers | 3.0 MiB |
| Validation and similarity checks | 2.0 MiB |
| Allocator overhead and safety reserve | 2.5 MiB |
| **Total** | **16.0 MiB** |

These are engineering budgets, not measured results. Actual allocations must be measured on target devices.

Implementation requirements:
- Bounded arena allocator per job.
- Explicit maximum input bytes.
- Explicit maximum paragraphs.
- Explicit maximum facts and entities.
- Explicit maximum output bytes.
- Reuse buffers where safe.
- Avoid unbounded `std::vector` growth.
- Avoid copying full source text unnecessarily.
- Avoid large temporary strings.
- Avoid recursive algorithms with unbounded depth.
- Avoid unbounded thread creation.
- Do not retain model tensors or inference contexts in the core.

The engine must return a specific resource-limit error when an input exceeds configured limits. It must not silently truncate facts and continue as if the article were complete.

# 9. Recommended initial limits

These are starting limits to validate through benchmarks.

| Limit | Initial value |
|---|---:|
| Input content | 512 KiB |
| Title | 2 KiB |
| Source count per job | 5 |
| Paragraph count | 256 |
| Facts per job | 256 |
| Entities per job | 128 |
| Evidence passages | 512 |
| Generated article | 32 KiB |
| Concurrent editorial jobs | 1 per engine instance |
| Core working memory | 16 MiB |

The application may configure lower limits for older devices.

A single job per instance is recommended initially to make memory accounting predictable. Parallelism can be introduced later using separate bounded job contexts.

# 10. Mobile-first execution

The native library must never perform long-running work on the Android UI thread.

Recommended execution:

```text
Android UI
   |
   v
JNI / Kotlin wrapper
   |
   v
Native job submission
   |
   v
Bounded worker
   |
   v
NewsBrain
   |
   v
Progress / completion callback
   |
   v
Android UI
```

Android:
- JNI bridge.
- Background executor.
- Job cancellation.
- Lifecycle-aware callback handling.
- Native library packaged for supported ABIs.

iOS:
- Objective-C++ or Swift bridge.
- Background task execution.
- Memory-pressure handling.
- Explicit cancellation and lifecycle handling.

Desktop:
- C ABI, C++ API and optional CLI test harness.

The core itself should not depend on Android, Flutter, UIKit, Qt or a browser engine.

# 11. Public API design

Use an opaque C API for cross-platform compatibility.

Prefer a single job-based editorial entry point over requiring applications to instantiate every internal module individually.

Illustrative API:

```c
typedef struct YallaBrain YallaBrain;
typedef struct YallaJob YallaJob;

typedef enum {
    YALLA_STATUS_OK = 0,
    YALLA_STATUS_INVALID_ARGUMENT,
    YALLA_STATUS_OUT_OF_MEMORY,
    YALLA_STATUS_INPUT_TOO_LARGE,
    YALLA_STATUS_CANCELLED,
    YALLA_STATUS_UNSUPPORTED_LANGUAGE,
    YALLA_STATUS_GENERATION_FAILED,
    YALLA_STATUS_VALIDATION_FAILED,
    YALLA_STATUS_INTERNAL_ERROR
} YallaStatus;

typedef struct {
    const char* text;
    const char* language;
    const char* title;
    const char* source_url;
    const char* publisher;
    int64_t published_at;
} YallaSourceInput;

typedef struct {
    const YallaSourceInput* sources;
    int32_t source_count;
    const char* output_language;
    const char* article_type;
    const char* editorial_style;
    int32_t target_length;
    uint32_t flags;
} YallaEditorialRequest;

YALLA_CORE_EXPORT YallaBrain* yalla_brain_create(
    const char* configuration_json
);

YALLA_CORE_EXPORT void yalla_brain_destroy(
    YallaBrain* brain
);

YALLA_CORE_EXPORT YallaStatus yalla_brain_write_article(
    YallaBrain* brain,
    const YallaEditorialRequest* request,
    char** result_json
);

YALLA_CORE_EXPORT void yalla_brain_cancel(
    YallaBrain* brain
);

YALLA_CORE_EXPORT void yalla_brain_free(
    void* memory
);

YALLA_CORE_EXPORT const char* yalla_brain_version(void);
```

This is a proposed API contract; implement and test its exact ownership and threading semantics before release.

Requirements:
- Every returned allocation must have a documented release function.
- Inputs are borrowed only for the duration explicitly documented.
- No returned pointer may refer to a temporary object that has already been destroyed.
- Null pointers and invalid lengths must be checked.
- Errors must be structured.
- The API must expose ABI version information.
- Cancellation must be safe.
- Callback lifetime and thread of execution must be documented.

# 12. Structured output

Return a JSON result containing the article and its evidence.

Example:

```json
{
  "status": "READY_WITH_WARNINGS",
  "article": {
    "headline": "Example original headline",
    "subtitle": "Optional explanatory subtitle",
    "introduction": "Original editorial introduction.",
    "body": [
      {
        "heading": null,
        "text": "First original paragraph.",
        "fact_ids": ["F001", "F002"]
      },
      {
        "heading": "Additional context",
        "text": "Second original paragraph.",
        "fact_ids": ["F003"]
      }
    ],
    "conclusion": "Evidence-supported closing paragraph.",
    "language": "en",
    "article_type": "general_news"
  },
  "editorial": {
    "angle": "Main development",
    "warnings": [
      "The source does not provide a completion date."
    ]
  },
  "provenance": {
    "source_ids": ["S001"],
    "fact_count": 3,
    "supported_claim_count": 3,
    "unsupported_claim_count": 0
  },
  "validation": {
    "fact_check": "passed",
    "similarity_check": "warning",
    "quality_check": "passed"
  }
}
```

The final schema must be versioned.

Do not expose internal chain-of-thought or private reasoning. Return concise editorial metadata, fact evidence and validation explanations instead.

# 13. Existing header redesign

The current `yalla_core.h` provides useful starting points:
- Task scheduler.
- News ingestion.
- Language detection.
- Deduplication.
- Classification.
- Entity extraction.
- Event clustering.
- Model management.
- Inference.
- Summarization.
- Translation.
- Provider adapters.
- News pipeline.

However, these modules are not yet a complete editorial architecture.

Required changes:

1. Make the editorial job the central public operation.
2. Add FactEngine, StoryEngine, EditorialPlanner, NewsWriter, FactGuard, SimilarityGuard and EditorialQualityEngine.
3. Separate content extraction from editorial understanding.
4. Separate deterministic writing from generative model execution.
5. Make model support optional.
6. Replace implicit pointer ownership with explicit ownership.
7. Replace the current incomplete scheduler wrapper with a real bounded implementation.
8. Correct the C ABI so the public header can compile as C as well as C++.
9. Replace raw pointer-based result wrappers with owned C++ value types.
10. Add ABI versioning, structured errors and cancellation semantics.
11. Remove or redesign APIs that return pointers whose lifetime is unclear.
12. Ensure no result contains pointers into freed entity, cluster or provider buffers.

The existing C++ wrapper implementations that copy `YallaEntity`, `YallaCluster` and `YallaProviderArticle` structures before freeing their backing allocations must be corrected. The copied structures currently retain pointers that may no longer be valid.

The existing `TaskScheduler::submit()` implementation returns `false` unconditionally and must be implemented rather than left as a stub.

# 14. Recommended source tree

```text
NewsBrain/
|
+-- CMakeLists.txt
+-- README.md
+-- LICENSE
|
+-- include/
|   +-- yalla/
|       +-- yalla_brain.h
|       +-- yalla_types.h
|       +-- yalla_errors.h
|       +-- yalla_editorial.h
|       +-- yalla_generation_backend.h
|       +-- yalla_core.hpp
|
+-- src/
|   +-- api/
|   |   +-- c_api.cpp
|   |   +-- result_serializer.cpp
|   |
|   +-- core/
|   |   +-- brain.cpp
|   |   +-- job_context.cpp
|   |   +-- bounded_allocator.cpp
|   |   +-- cancellation.cpp
|   |
|   +-- input/
|   |   +-- input_adapter.cpp
|   |   +-- html_text_extractor.cpp
|   |   +-- text_normalizer.cpp
|   |
|   +-- language/
|   |   +-- language_detector.cpp
|   |   +-- arabic_normalizer.cpp
|   |   +-- tokenizer.cpp
|   |
|   +-- intelligence/
|   |   +-- content_understanding.cpp
|   |   +-- fact_engine.cpp
|   |   +-- entity_engine.cpp
|   |   +-- event_engine.cpp
|   |   +-- source_evidence.cpp
|   |
|   +-- editorial/
|   |   +-- story_engine.cpp
|   |   +-- editorial_planner.cpp
|   |   +-- news_writer.cpp
|   |   +-- deterministic_writer.cpp
|   |   +-- article_composer.cpp
|   |
|   +-- generation/
|   |   +-- generation_backend.cpp
|   |   +-- remote_backend.cpp
|   |   +-- local_backend.cpp
|   |
|   +-- validation/
|   |   +-- fact_guard.cpp
|   |   +-- similarity_guard.cpp
|   |   +-- editorial_quality.cpp
|   |
|   +-- platform/
|       +-- android/
|       +-- ios/
|       +-- desktop/
|
+-- tests/
|   +-- unit/
|   +-- integration/
|   +-- editorial/
|   +-- memory/
|   +-- multilingual/
|   +-- abi/
|   +-- fuzz/
|
+-- benchmarks/
|   +-- memory_benchmark.cpp
|   +-- latency_benchmark.cpp
|   +-- editorial_benchmark.cpp
|
+-- examples/
    +-- basic_article.cpp
    +-- multi_source_article.cpp
    +-- android_jni/
```

# 15. Testing and acceptance criteria

## A. Memory tests

- Run repeated jobs without increasing retained memory.
- Test maximum-size input.
- Test malformed UTF-8.
- Test maximum paragraph and fact counts.
- Test cancellation during every major stage.
- Test allocator exhaustion.
- Confirm all job allocations are released.
- Measure peak native working memory on real Android devices.

Acceptance: the core stays within 16 MiB under the declared maximum input profile, including allocator overhead.

## B. Editorial tests

Build a multilingual test corpus containing:
- One-source breaking news.
- Multiple-source coverage of one event.
- Contradictory reports.
- Government announcements.
- Allegations.
- Opinions.
- Sports reports.
- Economic news.
- Incomplete articles.
- Poorly extracted webpage text.
- Mixed Arabic and French content.

Human reviewers should evaluate:
- Accuracy.
- Originality.
- Coherence.
- Professional style.
- Language quality.
- Attribution.
- Missing information.
- Unsupported information.

## C. Originality tests

The output must not simply preserve source sentence order.

Evaluate:
- Headline originality.
- Sentence overlap.
- Distinctive phrase reuse.
- Paragraph-order similarity.
- Independent editorial structure.
- Semantic preservation.

Use human review in addition to automated similarity tests.

## D. Fact accuracy tests

Create cases containing:
- Incorrect numbers.
- Conflicting dates.
- Unsupported causal claims.
- Allegations.
- Unverified statements.
- Missing completion dates.
- Ambiguous names.

Acceptance: the engine must not silently turn uncertainty into certainty.

## E. ABI tests

- Compile the public header as C.
- Compile the public header as C++.
- Test all supported Android ABIs.
- Test repeated create/destroy cycles.
- Test concurrent API misuse.
- Test pointer ownership.
- Run AddressSanitizer and UndefinedBehaviorSanitizer where available.
- Run fuzz tests on all input parsers.

# 16. Implementation phases

## Phase 1 — Production foundation

Implement:
- Correct public C ABI.
- JobContext.
- Bounded allocator.
- Structured errors.
- Cancellation.
- InputAdapter.
- LanguageEngine.
- JSON result serializer.

Deliverable: a stable, testable native library.

## Phase 2 — Understanding

Implement:
- ContentUnderstandingEngine.
- FactEngine.
- EntityEngine.
- SourceEvidenceEngine.
- EventUnderstandingEngine.

Deliverable: a structured fact sheet from raw news content.

## Phase 3 — Editorial brain

Implement:
- StoryEngine.
- EditorialPlanner.
- DeterministicWriter.
- ArticleComposer.

Deliverable: a new article based on structured facts, with a clearly identified deterministic writing mode.

## Phase 4 — Validation

Implement:
- FactGuard.
- SimilarityGuard.
- EditorialQualityEngine.
- EditorialDecision.

Deliverable: validated articles with warnings and provenance.

## Phase 5 — Generative intelligence

Implement:
- GenerationBackend interface.
- Optional remote adapter.
- Optional local model adapter.
- Model capability detection.
- Model memory checks.

Deliverable: natural, fluent article generation without making the core dependent on a large model.

## Phase 6 — Mobile production

Implement:
- Android JNI integration.
- Background processing.
- Lifecycle-safe callbacks.
- Cancellation.
- Memory-pressure handling.
- Device benchmarks.

Then implement iOS and desktop bridges.

# 17. Final production definition

NewsBrain is complete only when it can accept imperfect news content, understand the information it contains, independently plan a new article, write that article in a professional editorial style, validate its factual support, identify limitations, and release all temporary memory after returning the result.

The core must remain usable without a generative model.

The optional generative backend must improve natural writing quality without compromising the factual evidence model.

**The most important acceptance test is not whether the engine can extract a clean article from a webpage. It is whether it can take the information from that article, understand the news, and write a genuinely new, accurate and coherent article of its own.**
