cmake_minimum_required(VERSION 3.14)
project(newsBrain LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(NEWS_BRAIN_SOURCES
    src/page_skeleton.cpp
    src/html_parser.cpp
    src/http_fetcher.cpp
    src/page_scanner.cpp
    src/article_brain.cpp
    src/article_rebuilder.cpp
    src/news_brain.cpp
    ../yalla_engine/arabic_nlp.cpp
)

# Shared library (newsBrain.dll / libnewsBrain.so)
add_library(newsBrain SHARED
    ${NEWS_BRAIN_SOURCES}
)

target_include_directories(newsBrain PUBLIC
    include
    ../yalla_engine
)

target_compile_definitions(newsBrain PRIVATE
    NEWSBRAIN_EXPORTS
)

if(WIN32)
    target_link_libraries(newsBrain PRIVATE winhttp)
endif()

# CLI executable
add_executable(news_brain_cli
    src/cli_main.cpp
    ${NEWS_BRAIN_SOURCES}
)

target_include_directories(news_brain_cli PUBLIC
    include
    ../yalla_engine
)

if(WIN32)
    target_link_libraries(news_brain_cli PRIVATE winhttp)
endif()

set_target_properties(newsBrain PROPERTIES
    OUTPUT_NAME "newsBrain"
    PREFIX ""
    POSITION_INDEPENDENT_CODE ON
)
