package inoov.app.yallanews

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * Native alarm manager that sets exact wake-up alarms for each prayer time.
 * When the alarm fires, [PrayerNotificationReceiver] starts [AdhanAudioService]
 * which plays the adhan audio even when the app is completely closed.
 */
object PrayerAlarmManager {

    const val ACTION_PRAYER_FIRE = "inoov.app.yallanews.PRAYER_NOTIFICATION_FIRE"
    const val ACTION_STOP_ADHAN = "inoov.app.yallanews.STOP_ADHAN"
    const val EXTRA_MUEZZIN = "muezzin_key"
    const val EXTRA_PRAYER_NAME = "prayer_name"

    private fun prayerRequestCode(prayerName: String): Int {
        // Stable unique code per prayer name so cancelling works.
        return when (prayerName) {
            "Fajr" -> 1001
            "Dhuhr" -> 1002
            "Asr" -> 1003
            "Maghrib" -> 1004
            "Isha" -> 1005
            else -> 1000
        }
    }

    /// Schedule an exact wake-up alarm for a prayer time.
    fun schedulePrayerAlarm(
        context: Context,
        prayerTimeMillis: Long,
        prayerName: String,
        muezzin: String
    ) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(context, PrayerNotificationReceiver::class.java).apply {
            action = ACTION_PRAYER_FIRE
            putExtra(EXTRA_MUEZZIN, muezzin)
            putExtra(EXTRA_PRAYER_NAME, prayerName)
        }
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            prayerRequestCode(prayerName),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                prayerTimeMillis,
                pendingIntent
            )
        } else {
            alarmManager.setExact(
                AlarmManager.RTC_WAKEUP,
                prayerTimeMillis,
                pendingIntent
            )
        }
    }

    /// Cancel a previously scheduled prayer alarm.
    fun cancelPrayerAlarm(context: Context, prayerName: String) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(context, PrayerNotificationReceiver::class.java).apply {
            action = ACTION_PRAYER_FIRE
            putExtra(EXTRA_PRAYER_NAME, prayerName)
        }
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            prayerRequestCode(prayerName),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        alarmManager.cancel(pendingIntent)
    }

    /// Cancel all prayer alarms (used when re-caching a new year/month).
    fun cancelAllPrayerAlarms(context: Context) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        for (code in 1000..1005) {
            val intent = Intent(context, PrayerNotificationReceiver::class.java).apply {
                action = ACTION_PRAYER_FIRE
            }
            val pendingIntent = PendingIntent.getBroadcast(
                context, code, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            alarmManager.cancel(pendingIntent)
        }
    }
}