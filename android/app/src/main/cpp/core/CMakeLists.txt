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
    target_link_options(yalla_core PRIVATE "-Wl,-z,max-page-size=16384" "-Wl,-z,common-page-size=16384")

    # Find required libraries
    find_library(CURL_LIB curl)
    find_library(SSL_LIB ssl)
    find_library(CRYPTO_LIB crypto)
endif()

# ── llama.cpp Integration ──
# Disable features we don't need for mobile
set(LLAMA_BUILD_COMMON ON)
set(LLAMA_BUILD_TESTS OFF)
set(LLAMA_BUILD_TOOLS OFF)
set(LLAMA_BUILD_EXAMPLES OFF)
set(LLAMA_BUILD_SERVER OFF)
set(LLAMA_BUILD_APP OFF)
set(LLAMA_BUILD_UI OFF)
set(LLAMA_BUILD_MTMD OFF)
set(LLAMA_USE_SYSTEM_GGML OFF)
set(LLAMA_SUBPROCESS OFF)
set(LLAMA_CURL OFF)
set(LLAMA_OPENSSL ON)
set(GGML_LLAMAFILE ON)
set(GGML_NATIVE OFF)
set(GGML_CUDA OFF)
set(GGML_METAL OFF)
set(GGML_VULKAN OFF)
set(GGML_SYCL OFF)
set(GGML_CANN OFF)
set(GGML_RPC OFF)
set(GGML_OPENMP OFF)
set(BUILD_SHARED_LIBS ON)

# Add llama.cpp as subdirectory
add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/../../../../../third_party/llama.cpp llama_build)

# nlohmann/json from llama.cpp vendor
add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/../../../../../third_party/llama.cpp/vendor/nlohmann nlohmann_build)

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

add_library(yalla_core SHARED ${CORE_SOURCES})

target_include_directories(yalla_core PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${CMAKE_CURRENT_SOURCE_DIR}/../../../../../third_party/llama.cpp/include
    ${CMAKE_CURRENT_SOURCE_DIR}/../../../../../third_party/llama.cpp/vendor/nlohmann/include
)

target_compile_definitions(yalla_core PRIVATE
    YALLA_CORE_EXPORTS
    GGML_USE_LLAMAFILE
)

# Link against existing engines and llama.cpp
target_link_libraries(yalla_core PRIVATE
    android
    log
    yalla_engine
    newsBrain
    llama
    nlohmann_json
    ${CURL_LIB}
    ${SSL_LIB}
    ${CRYPTO_LIB}
)

set_target_properties(yalla_core PROPERTIES
    OUTPUT_NAME "yalla_core"
    SOVERSION "1"
    POSITION_INDEPENDENT_CODE TRUE
    CXX_STANDARD 23
    CXX_STANDARD_REQUIRED TRUE
    CXX_EXTENSIONS FALSE
)