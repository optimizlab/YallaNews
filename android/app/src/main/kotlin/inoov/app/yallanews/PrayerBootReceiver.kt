package inoov.app.yallanews

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationManagerCompat

/**
 * Broadcast receiver that reschedules prayer time notifications after device
 * reboot. On boot, it notifies the Flutter side via a method channel so the
 * prayer reminders can be re-registered from cached prayer times.
 */
class PrayerBootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (Intent.ACTION_BOOT_COMPLETED != intent.action) return

        // Check that notifications are enabled before rescheduling.
        if (NotificationManagerCompat.from(context).areNotificationsEnabled()) {
            // Signal the Flutter engine to reschedule prayer notifications.
            // The Dart side listens for this via a MethodChannel.
            val intent2 = Intent("inoov.app.yallanews.PRAYER_BOOT_COMPLETED")
            intent2.addFlags(Intent.FLAG_INCLUDE_STOPPED_PACKAGES)
            context.sendBroadcast(intent2)
        }
    }
}
