# C++ Unit Tests for yalla_core module
# Add to core/CMakeLists.txt when GoogleTest is available

cmake_minimum_required(VERSION 3.20)
project(yalla_core_tests LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Find GoogleTest
find_package(GTest REQUIRED)

# Test executable
add_executable(yalla_core_tests
    test_task_scheduler.cpp
    test_language_detector.cpp
    test_deduplicator.cpp
    test_classifier.cpp
    test_entity_extractor.cpp
    test_event_clusterer.cpp
    test_model_manager.cpp
)

target_link_libraries(yalla_core_tests PRIVATE
    GTest::GTest
    GTest::Main
    yalla_core
)

add_test(NAME yalla_core_tests COMMAND yalla_core_tests)