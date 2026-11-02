package inoov.app.yallanews

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Register the factory so Dart can show native ads through the
        // "yallanewsNativeAd" factory id (see NativeAdService in Dart).
        GoogleMobileAdsPlugin.registerNativeAdFactory(
            flutterEngine,
            "yallanewsNativeAd",
            YallaNewsNativeAdFactory(this),
        )
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        GoogleMobileAdsPlugin.unregisterNativeAdFactory(flutterEngine, "yallanewsNativeAd")
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
