package inoov.app.yallanews

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.IBinder
import androidx.core.app.NotificationCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Foreground service that plays the embedded adhan audio for ~30 seconds when
 * a prayer-time notification fires, even when the app is closed or hidden.
 *
 * It is started by [PrayerNotificationReceiver] (full-screen intent) and stops
 * itself once the adhan finishes or the 30s timer expires.
 *
 * The Dart side registers a [MethodChannel] named "inoov.app.yallanews/adhan_audio"
 * with handlers "startAdhan" / "stopAdhan" (see
 * AdhanAudioService in lib/services/prayer/adhan_audio_service.dart).
 */
class AdhanAudioService : Service() {

    companion object {
        const val EXTRA_MUEZZIN = "muezzin_key"
        const val CHANNEL_ID = "adhan_audio"
        const val NOTIFICATION_ID = 4001
        private const val METHOD_CHANNEL = "inoov.app.yallanews/adhan_audio"
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val muezzin = intent?.getStringExtra(EXTRA_MUEZZIN) ?: "makkah"
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification())

        // If the Flutter engine is alive, forward the request to Dart so it
        // can play the adhan audio.
        val engine = YallaNewsApp.engine
        if (engine != null) {
            val channel = MethodChannel(engine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            channel.invokeMethod("startAdhan", muezzin, null)
        }

        // Safety auto-stop after 35s so the service never leaks.
        android.os.Handler(mainLooper).postDelayed({
            stopForeground(true)
            stopSelf(startId)
        }, 35_000)

        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createNotificationChannel() {
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager?
        if (manager == null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Adhan Audio",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Plays the adhan audio at prayer time"
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(): android.app.Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_yallanews)
            .setContentTitle("\u0623\u0630\u0627\u0646")
            .setContentText("\u062c\u0627\u0631\u064a \u062a\u0634\u063a\u064a\u0644 \u0635\u0648\u062a \u0627\u0644\u0623\u0630\u0627\u0646")
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setAutoCancel(true)
            .build()
    }
}