package inoov.app.yallanews

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Receiver triggered by the full-screen prayer notification intent. It starts
 * the [AdhanAudioService] foreground service so the adhan plays even when the
 * app is closed or in the background.
 */
class PrayerNotificationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != "inoov.app.yallanews.PRAYER_NOTIFICATION_FIRE") return
        val muezzin = intent.getStringExtra("muezzin_key") ?: "makkah"
        val serviceIntent = Intent(context, AdhanAudioService::class.java).apply {
            putExtra(AdhanAudioService.EXTRA_MUEZZIN, muezzin)
        }
        context.startService(serviceIntent)
        Log.d("PrayerNotificationReceiver", "Starting adhan audio service for $muezzin")
    }
}