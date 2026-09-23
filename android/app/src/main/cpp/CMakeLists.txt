# Android NDK CMakeLists.txt for yalla_engine native library

cmake_minimum_required(VERSION 3.18)
project(yalla_engine LANGUAGES CXX)

# Android platform detection
if(CMAKE_SYSTEM_NAME STREQUAL "Android")
    set(CMAKE_ANDROID_STL_TYPE "gnustd")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -std=c++17 -fPIC")
    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -fPIC")
else()
    message(WARNING "This CMakeLists.txt is intended for Android NDK build")
endif()

# Source files - yalla_engine sources are in ../../../windows/yalla_engine/
set(YALLA_ENGINE_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../../windows/yalla_engine")

file(GLOB_RECURSE YALLA_ENGINE_SOURCES
    "${YALLA_ENGINE_ROOT}/*.cpp"
)

add_library(yalla_engine SHARED ${YALLA_ENGINE_SOURCES})

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