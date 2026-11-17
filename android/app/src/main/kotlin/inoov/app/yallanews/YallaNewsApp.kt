package inoov.app.yallanews

import io.flutter.embedding.engine.FlutterEngine

/** Holds a reference to the active FlutterEngine so background services can
 *  communicate with Dart via MethodChannels. */
class YallaNewsApp {
    companion object {
        @Volatile var engine: FlutterEngine? = null
    }
}