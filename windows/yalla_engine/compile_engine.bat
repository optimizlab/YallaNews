@echo off
echo ===================================================
echo   Compiling YallaNews Native C++ Engines (MinGW)
echo ===================================================

echo.
echo 1. Compiling Shared Native Library: yalla_engine.dll...
g++ -I. -O3 -shared -o yalla_engine.dll yalla_engine.cpp arabic_nlp.cpp cluster.cpp -fPIC -std=c++17
if %ERRORLEVEL% EQU 0 (
    echo [SUCCESS] Compiled yalla_engine.dll successfully.
) else (
    echo [ERROR] Failed compiling yalla_engine.dll.
    exit /b 1
)

echo.
echo 2. Compiling Standalone Socket Server: yalla_engine.exe...
g++ -I. -O3 -o yalla_engine.exe server.cpp yalla_engine.cpp arabic_nlp.cpp cluster.cpp -lws2_32 -std=c++17
if %ERRORLEVEL% EQU 0 (
    echo [SUCCESS] Compiled yalla_engine.exe successfully.
) else (
    echo [ERROR] Failed compiling yalla_engine.exe.
    exit /b 1
)

echo.
echo ===================================================
echo   Compilation Finished! Native engines ready.
echo ===================================================
