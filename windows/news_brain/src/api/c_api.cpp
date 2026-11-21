#include "yalla_brain.h"
#include "yalla_types.h"
#include "yalla_errors.h"

#include "core/brain.h"
#include "core/job_context.h"
#include "input/input_adapter.h"
#include "language/language_detector.h"
#include "intelligence/content_understanding.h"
#include "intelligence/fact_engine.h"
#include "intelligence/EntityEngine.h"
#include "intelligence/event_engine.h"
#include "intelligence/source_evidence.h"
#include "editorial/story_engine.h"
#include "editorial/editorial_planner.h"
#include "editorial/news_writer.h"
#include "editorial/deterministic_writer.h"
#include "validation/fact_guard.h"
#include "validation/similarity_guard.h"
#include "validation/editorial_quality.h"
#include "api/result_serializer.h"

#include <cstring>
#include <memory>
#include <string>
#include <vector>

#include <cstdio>

namespace {

const char* kSchemaVersion = "newsbrain.v1";

yalla::Status c_status(yalla::Status s) {
    return s;
}

} // namespace

extern "C" {

using namespace yalla;

YALLA_CORE_EXPORT YallaBrain* yalla_brain_create(const char* configuration_json) {
    yalla::BrainConfig config;
    (void)configuration_json; // reserved for future per-instance tuning
    auto* brain = new (std::nothrow) yalla::Brain(config);
    if (!brain || !brain->is_valid()) {
        delete brain;
        return nullptr;
    }
    return reinterpret_cast<YallaBrain*>(brain);
}

YALLA_CORE_EXPORT void yalla_brain_destroy(YallaBrain* brain) {
    delete reinterpret_cast<yalla::Brain*>(brain);
}

YALLA_CORE_EXPORT YallaStatus yalla_brain_write_article(
    YallaBrain* brain_c, const YallaEditorialRequest* request, char** result_json) {
    if (result_json) *result_json = nullptr;
    if (!brain_c || !request) return YALLA_STATUS_INVALID_ARGUMENT;

    auto* brain = reinterpret_cast<yalla::Brain*>(brain_c);
    auto job = std::make_unique<yalla::JobContext>(brain->config().limits);
    if (!job) return YALLA_STATUS_OUT_OF_MEMORY;

    std::string output_language = request->output_language ? request->output_language : "en";

    // Combine all source text for language detection.
    std::string combined;
    for (int32_t i = 0; i < request->source_count; ++i) {
        const char* t = request->sources[i].text ? request->sources[i].text : "";
        combined += t;
        combined += "\n";
    }

    yalla::LanguageDetector detector;
    yalla::Language lang = detector.detect(combined);
    if (lang == yalla::Language::Unknown) lang = yalla::Language::English;

    // Adapt each source: raw and normalized forms kept separate.
    std::vector<NormalizedSource> sources;
    sources.reserve(request->source_count);
    for (int32_t i = 0; i < request->source_count; ++i) {
        if (job->is_cancelled()) return YALLA_STATUS_CANCELLED;
        NormalizedSource ns;
        yalla::Status st = InputAdapter(*job).adapt(
            request->sources[i].text,
            request->sources[i].language ? request->sources[i].language : output_language.c_str(),
            request->sources[i].title,
            request->sources[i].source_url,
            request->sources[i].publisher,
            request->sources[i].published_at, ns);
        if (st != yalla::Status::OK) return static_cast<YallaStatus>(c_status(st));
        ns.detected_language = detector.language_code(lang);
        sources.push_back(std::move(ns));
    }

    // Build evidence per source (independence unknown unless established).
    SourceEvidenceEngine evidence_engine(*job);
    std::vector<Evidence> all_evidence;
    std::vector<std::string> source_ids;
    for (int32_t i = 0; i < (int32_t)sources.size(); ++i) {
        auto ev = evidence_engine.build_evidence(sources[i], i);
        all_evidence.insert(all_evidence.end(), ev.begin(), ev.end());
        source_ids.push_back(ev.empty() ? std::string("S000") : ev[0].source_id);
    }

    // Content understanding on the primary source.
    UnderstandingResult understanding;
    if (!sources.empty())
        understanding = ContentUnderstandingEngine(*job).understand(sources[0]);

    // Entities.
    EntityEngine entity_engine(*job);
    std::string primary_text = sources.empty() ? std::string() : sources[0].normalized_content;
    std::string primary_title = sources.empty() ? std::string() : sources[0].title;
    auto entities = entity_engine.extract_entities(primary_title, primary_text, output_language);
    (void)entities; // entities feed the writer in a full implementation

    // Facts: allegations never become established facts.
    FactEngine fact_engine(*job);
    auto facts = fact_engine.extract_facts(understanding, all_evidence, output_language);

    // Event representation (temporary, job-scoped).
    EventEngine event_engine(*job);
    EventRepresentation event = event_engine.classify(primary_title, primary_text, understanding);

    // Story and editorial plan.
    StoryEngine story_engine(*job);
    auto story = story_engine.derive(understanding, event);

    EditorialPlanner planner(*job);
    EditorialPlan plan = planner.plan(story, facts, output_language,
                                      request->article_type ? request->article_type : "",
                                      request->target_length);

    // Generation via the deterministic backend (16 MiB core).
    DeterministicWriter backend(*job);
    GenerationOptions gen_opts;
    gen_opts.language = output_language;
    gen_opts.max_length = request->target_length > 0 ? request->target_length : 400;
    gen_opts.style = request->editorial_style ? request->editorial_style : "professional";
    gen_opts.require_attribution = true;

    GenerationRequest greq;
    greq.plan = &plan;
    greq.facts = &facts;
    greq.evidence = &all_evidence;
    greq.options = &gen_opts;
    greq.cancellation = nullptr;

    GenerationResult generated;
    yalla::Status gst = backend.generate(greq, generated);
    if (gst != yalla::Status::OK) return static_cast<YallaStatus>(c_status(gst));

    // Validation: facts against evidence.
    FactGuard fact_guard(*job);
    std::string body_first = generated.body.empty()
        ? std::string() : generated.body.front().second;
    auto checks = fact_guard.check_article(
        generated.introduction + "\n" + body_first + "\n" + generated.conclusion,
        facts, all_evidence);
    bool fact_ok = fact_guard.all_supported(checks) || facts.empty();

    // Similarity against source.
    SimilarityGuard similarity_guard(*job);
    std::string source_text = sources.empty() ? std::string() : sources[0].normalized_content;
    auto sim = similarity_guard.compare(generated.introduction, source_text, generated.headline);

    // Editorial quality.
    EditorialQualityEngine quality_engine(*job);
    auto quality = quality_engine.evaluate(generated.introduction, generated.headline, output_language);

    // Editorial decision.
    YallaEditorialDecision decision = YALLA_EDITION_READY_WITH_WARNINGS;
    std::string fact_check_str = "passed";
    std::string similarity_check_str = "passed";
    std::string quality_check_str = "passed";
    std::vector<std::string> out_warnings;

    if (!fact_ok) {
        decision = YALLA_EDITION_NEEDS_REVIEW;
        fact_check_str = "warning";
        out_warnings.push_back("Some statements lack supporting evidence.");
    }
    if (sim.score > 0.30) {
        similarity_check_str = "warning";
        out_warnings.push_back("Similarity to source exceeds threshold; review for originality.");
    }
    if (quality.unsupported_statements || quality.score < 0.6) {
        quality_check_str = "warning";
        out_warnings.push_back("Quality checks flagged unsupported or unclear statements.");
    }
    if (understanding.main_event.empty() && facts.empty()) {
        decision = YALLA_EDITION_REJECTED;
    }

    int32_t supported = 0, unsupported = 0;
    for (const auto& f : facts) {
        if (f.fact_type == "confirmed") ++supported;
        else if (f.fact_type == "allegation" || f.fact_type == "unknown") ++unsupported;
    }

    std::string json = yalla::serialize_result(
        kSchemaVersion, decision, generated, plan, out_warnings, source_ids,
        static_cast<int32_t>(facts.size()), supported, unsupported,
        fact_check_str, similarity_check_str, quality_check_str);

    char* out = new (std::nothrow) char[json.size() + 1];
    if (!out) return YALLA_STATUS_OUT_OF_MEMORY;
    std::memcpy(out, json.c_str(), json.size() + 1);
    *result_json = out;
    return YALLA_STATUS_OK;
}

YALLA_CORE_EXPORT void yalla_brain_cancel(YallaBrain* brain_c) {
    if (!brain_c) return;
    auto* brain = reinterpret_cast<yalla::Brain*>(brain_c);
    brain->cancel();
}

YALLA_CORE_EXPORT void yalla_brain_free(void* memory) {
    delete[] static_cast<char*>(memory);
}

YALLA_CORE_EXPORT const char* yalla_brain_version(void) {
    return "NewsBrain 1.0.0";
}

YALLA_CORE_EXPORT int32_t yalla_brain_abi_version(void) {
    return YALLA_CORE_ABI_VERSION;
}

} // extern "C"
