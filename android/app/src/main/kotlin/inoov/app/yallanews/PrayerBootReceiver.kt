package inoov.app.yallanews

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationManagerCompat

/**
 * Broadcast receiver that restores prayer-time alarms after device reboot.
 *
 * On [Intent.ACTION_BOOT_COMPLETED] it reads the alarms persisted by
 * [PrayerAlarmManager] and re-registers each exact wake-up alarm, so Athan
 * playback survives device reboot without the Flutter engine running.
 *
 * Only future alarms are restored; past alarms (missed while the device was
 * off) are not re-fired.
 */
class PrayerBootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != "inoov.app.yallanews.PRAYER_BOOT_COMPLETED") return

        if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) return

        val now = System.currentTimeMillis()
        val alarms = PrayerAlarmManager.getStoredAlarms(context)
        val alarmManager =
            context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

        for (entry in alarms) {
            // Skip alarms that are already in the past so we do not fire a
            // burst of missed prayers on every boot.
            if (entry.prayerTimeMillis <= now) continue

            val fireIntent = Intent(context, PrayerNotificationReceiver::class.java).apply {
                putExtra(PrayerAlarmManager.EXTRA_MUEZZIN, entry.muezzin)
                putExtra(PrayerAlarmManager.EXTRA_PRAYER_NAME, entry.prayerName)
                putExtra(PrayerAlarmManager.EXTRA_REQUEST_CODE, entry.requestCode)
            }
            fireIntent.action = PrayerAlarmManager.ACTION_PRAYER_FIRE
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                entry.requestCode,
                fireIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    entry.prayerTimeMillis,
                    pendingIntent
                )
            } else {
                alarmManager.setExact(
                    AlarmManager.RTC_WAKEUP,
                    entry.prayerTimeMillis,
                    pendingIntent
                )
            }
            android.util.Log.d(
                "PrayerBootReceiver",
                "Restored alarm ${entry.requestCode} for ${entry.prayerName}"
            )
        }
    }
}
