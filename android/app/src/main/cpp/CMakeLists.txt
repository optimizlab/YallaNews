# Android NDK CMakeLists.txt for yalla_engine native library

cmake_minimum_required(VERSION 3.18)
project(yalla_engine LANGUAGES CXX)

# Support 16 KB page sizes for Android 15+ (Google Play requirement)
set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384")
set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384")
add_link_options("-Wl,-z,max-page-size=16384" "-Wl,-z,common-page-size=16384")

if(CMAKE_SYSTEM_NAME STREQUAL "Android")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -std=c++17 -fPIC")
    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -fPIC")
else()
    message(WARNING "This CMakeLists.txt is intended for Android NDK build")
endif()

# Source files - yalla_engine sources are in ../../../../../windows/yalla_engine/
set(YALLA_ENGINE_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../windows/yalla_engine")

file(GLOB_RECURSE YALLA_ENGINE_SOURCES
    "${YALLA_ENGINE_ROOT}/*.cpp"
)

# Exclude Windows-only server.cpp from Android builds
list(REMOVE_ITEM YALLA_ENGINE_SOURCES "${YALLA_ENGINE_ROOT}/server.cpp")

add_library(yalla_engine SHARED ${YALLA_ENGINE_SOURCES})

target_link_options(yalla_engine PRIVATE "-Wl,-z,max-page-size=16384" "-Wl,-z,common-page-size=16384")

target_link_options(yalla_engine PRIVATE "-Wl,-z,max-page-size=16384" "-Wl,-z,common-page-size=16384")

set_target_properties(yalla_engine PROPERTIES
    OUTPUT_NAME "yalla_engine"
    SOVERSION "1"
    POSITION_INDEPENDENT_CODE TRUE
    CXX_STANDARD 17
    CXX_STANDARD_REQUIRED TRUE
    CXX_EXTENSIONS FALSE
)

target_include_directories(yalla_engine PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${YALLA_ENGINE_ROOT}
)

target_link_libraries(yalla_engine PRIVATE android log)

# ── newsBrain Native Engine for Android ──
set(NEWS_BRAIN_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../windows/news_brain")

set(NEWS_BRAIN_SOURCES
    "${NEWS_BRAIN_ROOT}/src/page_skeleton.cpp"
    "${NEWS_BRAIN_ROOT}/src/html_parser.cpp"
    "${NEWS_BRAIN_ROOT}/src/http_fetcher.cpp"
    "${NEWS_BRAIN_ROOT}/src/page_scanner.cpp"
    "${NEWS_BRAIN_ROOT}/src/article_brain.cpp"
    "${NEWS_BRAIN_ROOT}/src/article_rebuilder.cpp"
    "${NEWS_BRAIN_ROOT}/src/news_brain.cpp"
)

add_library(newsBrain SHARED ${NEWS_BRAIN_SOURCES})

target_link_options(newsBrain PRIVATE "-Wl,-z,max-page-size=16384" "-Wl,-z,common-page-size=16384")

target_link_options(newsBrain PRIVATE "-Wl,-z,max-page-size=16384" "-Wl,-z,common-page-size=16384")

set_target_properties(newsBrain PROPERTIES
    OUTPUT_NAME "newsBrain"
    SOVERSION "1"
    POSITION_INDEPENDENT_CODE TRUE
    CXX_STANDARD 17
    CXX_STANDARD_REQUIRED TRUE
    CXX_EXTENSIONS FALSE
)

target_include_directories(newsBrain PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${NEWS_BRAIN_ROOT}/include
    ${YALLA_ENGINE_ROOT}
)

target_link_libraries(newsBrain PRIVATE android log yalla_engine)