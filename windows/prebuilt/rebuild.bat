@echo off
REM ============================================================
REM  YallaNews - Rebuild news_brain C++ DLL (Debug + Release)
REM  Run this ONLY when you change C++ source files in
REM  windows/news_brain/src/ or windows/yalla_engine/
REM  After running, the prebuilt/ DLLs are updated and
REM  the next "flutter run -d windows" will pick them up fast.
REM ============================================================

set ROOT=%~dp0..\..
set BUILD_DIR=%ROOT%\build\windows\x64

echo [1/3] Configuring CMake...
cmake -S "%ROOT%\windows" -B "%BUILD_DIR%" -G "Visual Studio 17 2022" -A x64

echo [2/3] Building Debug DLL...
cmake --build "%BUILD_DIR%" --config Debug --target newsBrain
copy /Y "%BUILD_DIR%\news_brain\Debug\newsBrain.dll" "%~dp0Debug\newsBrain.dll"
copy /Y "%BUILD_DIR%\news_brain\Debug\newsBrain.lib" "%~dp0Debug\newsBrain.lib"

echo [3/3] Building Release DLL...
cmake --build "%BUILD_DIR%" --config Release --target newsBrain
copy /Y "%BUILD_DIR%\news_brain\Release\newsBrain.dll" "%~dp0Release\newsBrain.dll"
copy /Y "%BUILD_DIR%\news_brain\Release\newsBrain.lib" "%~dp0Release\newsBrain.lib"

echo Done! Prebuilt DLLs updated. Now run: flutter run -d windows

