@echo off
echo ===================================================
echo   Compiling newsBrain C++ Shared DLL and CLI (MinGW)
echo ===================================================

cd /d "%~dp0"

echo.
echo 1. Compiling Shared Native Library: newsBrain.dll...
g++ -Iinclude -I../yalla_engine -O3 -shared -o newsBrain.dll ^
    src/page_skeleton.cpp ^
    src/html_parser.cpp ^
    src/http_fetcher.cpp ^
    src/page_scanner.cpp ^
    src/article_brain.cpp ^
    src/article_rebuilder.cpp ^
    src/news_brain.cpp ^
    -lwinhttp -std=c++17 -DNEWSBRAIN_EXPORTS

if %ERRORLEVEL% EQU 0 (
    echo [SUCCESS] Compiled newsBrain.dll successfully.
) else (
    echo [ERROR] Failed compiling newsBrain.dll.
    exit /b 1
)

echo.
echo 2. Compiling Standalone Testing CLI: news_brain_cli.exe...
g++ -Iinclude -O3 -o news_brain_cli.exe ^
    src/cli_main.cpp ^
    -L. -lnewsBrain -std=c++17

if %ERRORLEVEL% EQU 0 (
    echo [SUCCESS] Compiled news_brain_cli.exe successfully.
) else (
    echo [ERROR] Failed compiling news_brain_cli.exe.
    exit /b 1
)

echo.
echo 3. Copying newsBrain.dll to project root and runner folders for Flutter FFI...
copy /Y newsBrain.dll ..\..\newsBrain.dll >nul 2>&1
copy /Y newsBrain.dll ..\runner\newsBrain.dll >nul 2>&1
if exist "..\..\build\windows\x64\runner\Debug" (
    copy /Y newsBrain.dll "..\..\build\windows\x64\runner\Debug\newsBrain.dll" >nul 2>&1
)
if exist "..\..\build\windows\x64\runner\Release" (
    copy /Y newsBrain.dll "..\..\build\windows\x64\runner\Release\newsBrain.dll" >nul 2>&1
)

echo.
echo ===================================================
echo   newsBrain compilation finished successfully!
echo ===================================================
