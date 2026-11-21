@echo off

:: Stop any running Gradle daemons
echo Stopping Gradle daemons...
.\gradlew --stop

:: Delete all Kotlin incremental cache folders
echo Deleting Kotlin incremental caches...
for /d %%d in (build\*\kotlin\compileDebugKotlin\cacheable) do rd /s /q "%%d"

:: Run Flutter clean and rebuild (pass through any arguments)
echo Running Flutter clean and rebuild...
flutter clean
flutter pub get
flutter run %*
