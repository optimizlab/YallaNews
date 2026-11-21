package inoov.app.yallanews

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import java.io.IOException

/**
 * Foreground service that plays the embedded adhan audio natively via MediaPlayer
 * when a prayer-time alarm fires, even when the app is closed or hidden.
 *
 * It is started by [PrayerNotificationReceiver] and stops itself once the adhan
 * finishes or the 35s safety timer expires.
 *
 * The foreground notification includes a "Stop Adhan" action button that sends
 * [PrayerAlarmManager.ACTION_STOP_ADHAN] to stop playback early.
 */
class AdhanAudioService : Service(), MediaPlayer.OnCompletionListener, MediaPlayer.OnErrorListener {

    companion object {
        const val EXTRA_MUEZZIN = "muezzin_key"
        const val EXTRA_PRAYER_NAME = "prayer_name"
        const val EXTRA_START_FROM_ALARM = "start_from_alarm"
        const val CHANNEL_ID = "adhan_audio"
        const val NOTIFICATION_ID = 4001
        const val ACTION_STOP = "inoov.app.yallanews.STOP_ADHAN_FROM_NOTIFICATION"
    }

    private var mediaPlayer: MediaPlayer? = null
    private var stopTimerHandler: Handler? = null
    private var stopTimerRunnable: Runnable? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val muezzin = intent?.getStringExtra(EXTRA_MUEZZIN) ?: "makkah"
        val prayerName = intent?.getStringExtra(EXTRA_PRAYER_NAME) ?: "Prayer"
        val startFromAlarm = intent?.getBooleanExtra(EXTRA_START_FROM_ALARM, false) ?: false

        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification(prayerName))

        // Play the adhan natively via MediaPlayer (no Dart dependency).
        playAdhan(muezzin)

        // Safety auto-stop after 35s so the service never leaks.
        stopTimerHandler = Handler(Looper.getMainLooper())
        stopTimerRunnable = Runnable {
            stopSelf(startId)
        }
        stopTimerHandler?.postDelayed(stopTimerRunnable!!, 35_000)

        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        stopTimerHandler?.removeCallbacks(stopTimerRunnable!!)
        stopTimerHandler = null
        stopTimerRunnable = null
        mediaPlayer?.stop()
        mediaPlayer?.release()
        mediaPlayer = null
        super.onDestroy()
    }

    private fun createNotificationChannel() {
        val manager = getSystemService(android.content.Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
        val channel = android.app.NotificationChannel(
            CHANNEL_ID,
            "Adhan Audio",
            android.app.NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Adhan is playing"
            setShowBadge(false)
            lockscreenVisibility = androidx.core.app.NotificationCompat.VISIBILITY_PUBLIC
        }
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(prayerName: String): android.app.Notification {
        // Stop action: sends broadcast to PrayerNotificationReceiver which stops this service.
        val stopIntent = Intent(PrayerAlarmManager.ACTION_STOP_ADHAN)
        val stopPendingIntent = PendingIntent.getBroadcast(
            this, 5001, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return androidx.core.app.NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_yallanews)
            .setContentTitle("\u0623\u0630\u0627\u0646 - $prayerName")
            .setContentText("\u062c\u0627\u0631\u064a \u062a\u0634\u063a\u064a\u0644 \u0635\u0648\u062a \u0627\u0644\u0623\u0630\u0627\u0646")
            .setPriority(androidx.core.app.NotificationCompat.PRIORITY_HIGH)
            .setCategory(androidx.core.app.NotificationCompat.CATEGORY_ALARM)
            .setAutoCancel(false)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .addAction(androidx.core.app.NotificationCompat.Action(
                R.drawable.ic_stat_yallanews,
                "\u0625\u064a\u0642\u0641 \u0627\u0644\u0623\u0630\u0627\u0646",
                stopPendingIntent
            ))
            .build()
    }

    private fun playAdhan(muezzin: String) {
        val assetName = when (muezzin) {
            "makkah" -> "adhan_makkah.mp3"
            "afasy" -> "adhan_afasy.mp3"
            "qatami" -> "adhan_qatami.mp3"
            "imadi" -> "adhan_imadi.mp3"
            "madinah" -> "adhan_madinah.mp3"
            "egypt" -> "adhan_egypt.mp3"
            "yemen" -> "adhan_yemen.mp3"
            "iraq" -> "adhan_iraq.mp3"
            "turkish" -> "adhan_turkish.mp3"
            "moroccan" -> "adhan_moroccan.mp3"
            else -> "adhan_makkah.mp3"
        }

        mediaPlayer = MediaPlayer().apply {
            setOnCompletionListener(this@AdhanAudioService)
            setOnErrorListener(this@AdhanAudioService)
            setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            )
            try {
                val fd = assets.openFd("audio/adhan/$assetName")
                setDataSource(fd.fileDescriptor, fd.startOffset, fd.length)
                fd.close()
                prepare()
                start()
            } catch (e: IOException) {
                android.util.Log.e("AdhanAudioService", "Failed to play adhan: $e", e)
                stopSelf()
            }
        }
    }

    override fun onCompletion(mp: MediaPlayer?) {
        stopSelf()
    }

    override fun onError(mp: MediaPlayer?, what: Int, extra: Int): Boolean {
        android.util.Log.e("AdhanAudioService", "MediaPlayer error: what=$what extra=$extra")
        stopSelf()
        return true
    }
}