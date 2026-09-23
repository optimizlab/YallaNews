cmake_minimum_required(VERSION 3.14)
project(yalla_engine LANGUAGES CXX)

add_library(yalla_engine SHARED
    yalla_engine.cpp
    cluster.cpp
    arabic_nlp.cpp
)

target_compile_features(yalla_engine PUBLIC cxx_std_17)

target_compile_options(yalla_engine PRIVATE
    /W4
    /WX
    /wd"4100"
    /EHsc
)

target_compile_definitions(yalla_engine PRIVATE
    "_HAS_EXCEPTIONS=0"
    "$<$<CONFIG:Debug>:_DEBUG>"
    "UNICODE"
    "_UNICODE"
)

target_include_directories(yalla_engine PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
)

set_target_properties(yalla_engine PROPERTIES
    OUTPUT_NAME "yalla_engine"
    PREFIX ""
    SOVERSION "1"
    VERSION "1.0.0"
    POSITION_INDEPENDENT_CODE ON
)