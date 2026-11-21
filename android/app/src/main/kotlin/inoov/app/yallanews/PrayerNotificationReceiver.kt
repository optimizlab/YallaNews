package inoov.app.yallanews

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.MediaPlayer
import android.os.Handler
import android.os.Looper
import android.util.Log
import java.io.IOException

/**
 * Receiver triggered by exact alarms at prayer times. It starts the
 * [AdhanAudioService] foreground service which plays the adhan audio natively
 * (via MediaPlayer) so playback works even when the app is completely closed.
 *
 * It also handles the STOP_ADHAN action from the notification's stop button.
 */
class PrayerNotificationReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action
        when (action) {
            PrayerAlarmManager.ACTION_PRAYER_FIRE -> {
                val muezzin = intent?.getStringExtra(PrayerAlarmManager.EXTRA_MUEZZIN) ?: "makkah"
                val prayerName = intent?.getStringExtra(PrayerAlarmManager.EXTRA_PRAYER_NAME) ?: "Prayer"
                val serviceIntent = Intent(context, AdhanAudioService::class.java).apply {
                    putExtra(AdhanAudioService.EXTRA_MUEZZIN, muezzin)
                    putExtra(AdhanAudioService.EXTRA_PRAYER_NAME, prayerName)
                    putExtra(AdhanAudioService.EXTRA_START_FROM_ALARM, true)
                }
                context.startForegroundService(serviceIntent)
                Log.d("PrayerNotificationReceiver", "Starting adhan audio service for $prayerName ($muezzin)")
            }
            PrayerAlarmManager.ACTION_STOP_ADHAN -> {
                Log.d("PrayerNotificationReceiver", "Stopping adhan audio service")
                val stopIntent = Intent(context, AdhanAudioService::class.java)
                context.stopService(stopIntent)
            }
        }
    }
}