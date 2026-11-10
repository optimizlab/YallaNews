@echo off
REM ============================================================
REM  YallaNews - Quick Launcher for Windows Desktop
REM  Double-click this file to launch YallaNews with full GUI.
REM ============================================================

set RELEASE_EXE="%~dp0build\windows\x64\runner\Release\yalla_news.exe"

if exist %RELEASE_EXE% (
    start "" %RELEASE_EXE%
) else (
    echo Building YallaNews...
    cd /d "%~dp0"
    call flutter run -d windows --no-pub
)

