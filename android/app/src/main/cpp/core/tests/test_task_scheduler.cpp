#include "yalla_core.h"
#include <gtest/gtest.h>
#include <string>

TEST(TaskSchedulerTest, CreateAndDestroy) {
    auto* scheduler = yalla_task_scheduler_create(2);
    ASSERT_NE(scheduler, nullptr);
    yalla_task_scheduler_destroy(scheduler);
}

TEST(TaskSchedulerTest, SubmitTask) {
    auto* scheduler = yalla_task_scheduler_create(1);
    ASSERT_NE(scheduler, nullptr);

    bool callback_called = false;
    auto callback = [](bool success, const char* result, void* user_data) {
        *static_cast<bool*>(user_data) = true;
        ASSERT_TRUE(success);
        ASSERT_STREQ(result, "{\"success\":true,\"message\":\"Task completed\"}");
    };

    bool result = yalla_task_scheduler_submit(scheduler, "{\"test\":true}", callback, &callback_called);
    EXPECT_TRUE(result);

    // Give time for async execution
    std::this_thread::sleep_for(std::chrono::milliseconds(50));
    EXPECT_TRUE(callback_called);

    yalla_task_scheduler_destroy(scheduler);
}

TEST(TaskSchedulerTest, PendingCount) {
    auto* scheduler = yalla_task_scheduler_create(1);
    ASSERT_NE(scheduler, nullptr);

    EXPECT_EQ(yalla_task_scheduler_pending_count(scheduler), 0);

    auto callback = [](bool, const char*, void*) {};
    yalla_task_scheduler_submit(scheduler, "{}", callback, nullptr);
    EXPECT_EQ(yalla_task_scheduler_pending_count(scheduler), 1);

    yalla_task_scheduler_destroy(scheduler);
}

TEST(LanguageDetectorTest, CreateAndDestroy) {
    auto* detector = yalla_language_detector_create();
    ASSERT_NE(detector, nullptr);
    yalla_language_detector_destroy(detector);
}

TEST(LanguageDetectorTest, DetectArabic) {
    auto* detector = yalla_language_detector_create();
    ASSERT_NE(detector, nullptr);

    float confidence = 0;
    YallaLanguage lang = yalla_language_detector_detect(detector, "هذا نص عربي للاختبار", &confidence);
    EXPECT_EQ(lang, YALLA_LANG_ARABIC);
    EXPECT_GT(confidence, 0.3f);

    yalla_language_detector_destroy(detector);
}

TEST(LanguageDetectorTest, DetectEnglish) {
    auto* detector = yalla_language_detector_create();
    ASSERT_NE(detector, nullptr);

    float confidence = 0;
    YallaLanguage lang = yalla_language_detector_detect(detector, "This is English text for testing", &confidence);
    EXPECT_EQ(lang, YALLA_LANG_ENGLISH);
    EXPECT_GT(confidence, 0.5f);

    yalla_language_detector_destroy(detector);
}

TEST(LanguageDetectorTest, DetectFrench) {
    auto* detector = yalla_language_detector_create();
    ASSERT_NE(detector, nullptr);

    float confidence = 0;
    YallaLanguage lang = yalla_language_detector_detect(detector, "C'est un texte français pour tester", &confidence);
    EXPECT_EQ(lang, YALLA_LANG_FRENCH);
    EXPECT_GT(confidence, 0.3f);

    yalla_language_detector_destroy(detector);
}

TEST(LanguageDetectorTest, NormalizeArabic) {
    auto* detector = yalla_language_detector_create();
    ASSERT_NE(detector, nullptr);

    const char* normalized = yalla_language_detector_normalize(detector, YALLA_LANG_ARABIC, "آلُأَخْبَارُ");
    ASSERT_NE(normalized, nullptr);
    EXPECT_STREQ(normalized, "الاخبار");
    yalla_free_string(normalized);

    yalla_language_detector_destroy(detector);
}

TEST(DeduplicatorTest, CreateAndDestroy) {
    auto* dedup = yalla_deduplicator_create();
    ASSERT_NE(dedup, nullptr);
    yalla_deduplicator_destroy(dedup);
}

TEST(DeduplicatorTest, ExactDuplicate) {
    auto* dedup = yalla_deduplicator_create();
    ASSERT_NE(dedup, nullptr);

    YallaArticle article1{};
    article1.title = strdup("Breaking News: Major Event Happens Today");
    article1.content = strdup("This is the content of the breaking news article about a major event.");
    article1.url = strdup("https://example.com/news/1");

    YallaArticle article2{};
    article2.title = strdup("Breaking News: Major Event Happens Today");
    article2.content = strdup("This is the content of the breaking news article about a major event.");
    article2.url = strdup("https://example.com/news/2");

    float similarity = 0;
    bool is_dup1 = yalla_deduplicator_is_duplicate(dedup, &article1, &similarity);
    EXPECT_FALSE(is_dup1);

    yalla_deduplicator_add(dedup, &article1);

    bool is_dup2 = yalla_deduplicator_is_duplicate(dedup, &article2, &similarity);
    EXPECT_TRUE(is_dup2);
    EXPECT_GT(similarity, 0.8f);

    free(const_cast<char*>(article1.title));
    free(const_cast<char*>(article1.content));
    free(const_cast<char*>(article1.url));
    free(const_cast<char*>(article2.title));
    free(const_cast<char*>(article2.content));
    free(const_cast<char*>(article2.url));

    yalla_deduplicator_destroy(dedup);
}

TEST(ClassifierTest, CreateAndDestroy) {
    auto* classifier = yalla_classifier_create();
    ASSERT_NE(classifier, nullptr);
    yalla_classifier_destroy(classifier);
}

TEST(ClassifierTest, ClassifySports) {
    auto* classifier = yalla_classifier_create();
    ASSERT_NE(classifier, nullptr);

    float confidence = 0;
    const char* category = yalla_classifier_classify(classifier,
        "Football team wins championship",
        "The team scored three goals in the final match to win the league title.",
        "Team wins league championship",
        &confidence);

    ASSERT_NE(category, nullptr);
    EXPECT_STREQ(category, "sports");
    EXPECT_GT(confidence, 0.5f);
    yalla_free_string(category);

    yalla_classifier_destroy(classifier);
}

TEST(EntityExtractorTest, CreateAndDestroy) {
    auto* extractor = yalla_entity_extractor_create();
    ASSERT_NE(extractor, nullptr);
    yalla_entity_extractor_destroy(extractor);
}

TEST(EntityExtractorTest, ExtractPerson) {
    auto* extractor = yalla_entity_extractor_create();
    ASSERT_NE(extractor, nullptr);

    int32_t count = 0;
    YallaEntity* entities = yalla_entity_extractor_extract(extractor,
        "President Biden meets with Prime Minister",
        "President Joe Biden met with the Prime Minister yesterday to discuss trade.",
        "en", &count);

    EXPECT_GT(count, 0);
    bool found_person = false;
    for (int i = 0; i < count; ++i) {
        if (std::string(entities[i].type) == "person") {
            found_person = true;
            break;
        }
    }
    EXPECT_TRUE(found_person);

    yalla_entity_extractor_free_entities(entities, count);
    yalla_entity_extractor_destroy(extractor);
}

TEST(EventClustererTest, CreateAndDestroy) {
    auto* clusterer = yalla_event_clusterer_create();
    ASSERT_NE(clusterer, nullptr);
    yalla_event_clusterer_destroy(clusterer);
}

TEST(ModelManagerTest, CreateAndDestroy) {
    auto* manager = yalla_model_manager_create("./test_models");
    ASSERT_NE(manager, nullptr);
    yalla_model_manager_destroy(manager);
}

TEST(InferenceEngineTest, CreateAndDestroy) {
    auto* manager = yalla_model_manager_create("./test_models");
    ASSERT_NE(manager, nullptr);

    auto* engine = yalla_inference_engine_create(manager);
    ASSERT_NE(engine, nullptr);
    yalla_inference_engine_destroy(engine);

    yalla_model_manager_destroy(manager);
}

TEST(SummarizerTest, CreateAndDestroy) {
    auto* manager = yalla_model_manager_create("./test_models");
    ASSERT_NE(manager, nullptr);

    auto* engine = yalla_inference_engine_create(manager);
    ASSERT_NE(engine, nullptr);

    auto* summarizer = yalla_summarizer_create(engine);
    ASSERT_NE(summarizer, nullptr);
    yalla_summarizer_destroy(summarizer);

    yalla_inference_engine_destroy(engine);
    yalla_model_manager_destroy(manager);
}

TEST(TranslatorTest, CreateAndDestroy) {
    auto* manager = yalla_model_manager_create("./test_models");
    ASSERT_NE(manager, nullptr);

    auto* engine = yalla_inference_engine_create(manager);
    ASSERT_NE(engine, nullptr);

    auto* translator = yalla_translator_create(engine);
    ASSERT_NE(translator, nullptr);
    yalla_translator_destroy(translator);

    yalla_inference_engine_destroy(engine);
    yalla_model_manager_destroy(manager);
}

TEST(UtilsTest, VersionString) {
    const char* version = yalla_get_version();
    ASSERT_NE(version, nullptr);
    EXPECT_STRNE(version, "");
    yalla_free_string(version);
}

TEST(UtilsTest, FreeString) {
    const char* str = strdup("test");
    yalla_free_string(str);
    // Should not crash
}

int main(int argc, char** argv) {
    ::testing::InitGoogleTest(&argc, argv);
    return RUN_ALL_TESTS();
}