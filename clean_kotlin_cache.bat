@echo off

:: Stop any running Gradle daemons
echo Stopping Gradle daemons...
.\gradlew --stop

:: Delete Kotlin incremental cache folder
echo Deleting Kotlin incremental caches...
rd /s /q build\webview_flutter_android\kotlin\compileDebugKotlin\cacheable

:: Run Flutter clean and rebuild (pass through any arguments)
echo Running Flutter clean and rebuild...
flutter clean
flutter pub get
flutter run %*
