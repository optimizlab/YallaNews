@echo off
REM ============================================================
REM  YallaNews - Windows Debug Session with Hot Reload
REM  Double-click to open terminal with hot reload (r/R/q).
REM ============================================================

cd /d "%~dp0"
flutter run -d windows --no-pub
pause

