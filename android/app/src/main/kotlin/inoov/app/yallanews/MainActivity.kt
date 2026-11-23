package inoov.app.yallanews

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        YallaNewsApp.engine = flutterEngine

        // Native prayer alarm channel: Dart schedules exact alarms via this channel.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "inoov.app.yallanews/prayer_alarm")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "schedulePrayerAlarm" -> {
                        val args = call.arguments as? Map<*, *> ?: run {
                            result.error("INVALID_ARGS", "Expected map arguments", null)
                            return@setMethodCallHandler
                        }
                        val prayerTimeMillis = args["prayerTimeMillis"] as? Long ?: 0L
                        val prayerName = args["prayerName"] as? String ?: "Prayer"
                        val muezzin = args["muezzin"] as? String ?: "makkah"
                        val requestCode = args["requestCode"] as? Int ?: 1000
                        try {
                            PrayerAlarmManager.schedulePrayerAlarm(
                                this@MainActivity,
                                prayerTimeMillis,
                                prayerName,
                                muezzin,
                                requestCode
                            )
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("ALARM_ERROR", e.message, null)
                        }
                    }
                    "cancelAllPrayerAlarms" -> {
                        try {
                            PrayerAlarmManager.cancelAllPrayerAlarms(this@MainActivity)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("CANCEL_ERROR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // Register the factory so Dart can show native ads through the
        // "yallanewsNativeAd" factory id (see NativeAdService in Dart).
        GoogleMobileAdsPlugin.registerNativeAdFactory(
            flutterEngine,
            "yallanewsNativeAd",
            YallaNewsNativeAdFactory(this),
        )
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        YallaNewsApp.engine = null
        GoogleMobileAdsPlugin.unregisterNativeAdFactory(flutterEngine, "yallanewsNativeAd")
        super.cleanUpFlutterEngine(flutterEngine)
    }
}