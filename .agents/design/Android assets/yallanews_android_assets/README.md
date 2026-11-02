# YallaNews - Android brand assets (package: inoov.app.yallanews)

## Option A - copy by hand
Copy everything in `res/` into `android/app/src/main/res/` (merge folders).
`AndroidManifest.xml`:
```xml
<application android:icon="@mipmap/ic_launcher"
             android:roundIcon="@mipmap/ic_launcher_round" ...>
    <!-- Notification small icon + colour (Firebase Cloud Messaging) -->
    <meta-data android:name="com.google.firebase.messaging.default_notification_icon"
               android:resource="@drawable/ic_stat_yallanews"/>
    <meta-data android:name="com.google.firebase.messaging.default_notification_color"
               android:resource="@color/notification_accent"/>
</application>
```
If you use flutter_local_notifications use `'ic_stat_yallanews'` as the Android icon name.

## Option B - Flutter generator
Copy `flutter/assets/icon/` to `<project>/assets/icon/`, put `flutter/flutter_launcher_icons.yaml`
next to pubspec.yaml and run `dart run flutter_launcher_icons`. (Do not use both options at once.)

## What is inside
| File | Use |
|---|---|
| `../play_store_icon_512.png` | Play Console > Store listing > App icon (512x512 PNG, full-bleed; Google adds the rounded mask) |
| `res/mipmap-*/ic_launcher_foreground.png` | Adaptive icon foreground, 108dp canvas, artwork kept inside the 66dp safe zone |
| `res/mipmap-*/ic_launcher_background.png` | Adaptive icon background (navy gradient) |
| `res/mipmap-*/ic_launcher_monochrome.png` | Android 13+ themed icon layer |
| `res/mipmap-*/ic_launcher*.png` | Legacy launcher icons (48dp) for Android < 8 |
| `res/drawable-*/ic_stat_yallanews.png` | Status-bar notification icon, white on transparent (24dp) |
| `flutter/assets/icon/icon_1024.png` | 1024px master (also usable as iOS icon, no alpha) |
| `source/*.svg` | Vector sources |

## Brand
Navy #0B1322 -> #1D2D4D, accent red #FF4D55, white. Wordmark font: Poppins Bold.
