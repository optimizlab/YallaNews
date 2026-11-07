# Local flutter_tts patch

This directory is based on the MIT-licensed `flutter_tts` 4.2.5 package.
The upstream `android/build.gradle` applies the Kotlin Gradle Plugin, which is
not supported by AGP 9. The Android Gradle file here uses AGP's built-in Kotlin
compiler instead; the Dart and platform implementations are otherwise
unchanged.

The package requires Dart 3.12 and Flutter 3.44 to match the built-in Kotlin
toolchain used by this app. See `LICENSE` for the upstream license.
