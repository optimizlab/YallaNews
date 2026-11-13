# Core C++23 Module for YallaNews
cmake_minimum_required(VERSION 3.20)
project(yalla_core LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Platform-specific settings
if(CMAKE_SYSTEM_NAME STREQUAL "Android")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fPIC")
    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -fPIC")
endif()

# Source files
set(CORE_SOURCES
    src/task_scheduler.cpp
    src/news_ingestion.cpp
    src/language_detector.cpp
    src/deduplicator.cpp
    src/classifier.cpp
    src/entity_extractor.cpp
    src/event_clusterer.cpp
    src/model_manager.cpp
    src/inference_engine.cpp
    src/summarizer.cpp
    src/translator.cpp
    src/utils.cpp
    src/provider_adapters.cpp
    src/news_pipeline.cpp
)

add_library(yalla_core STATIC ${CORE_SOURCES})

target_include_directories(yalla_core PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${YALLA_ENGINE_ROOT}
)

target_compile_definitions(yalla_core PRIVATE
    YALLA_CORE_EXPORTS
)

# Link against system libraries only (no circular deps with yalla_engine/newsBrain)
target_link_libraries(yalla_core PRIVATE
    android
    log
)

set_target_properties(yalla_core PROPERTIES
    OUTPUT_NAME "yalla_core"
    SOVERSION "1"
    POSITION_INDEPENDENT_CODE TRUE
    CXX_STANDARD 23
    CXX_STANDARD_REQUIRED TRUE
    CXX_EXTENSIONS FALSE
)