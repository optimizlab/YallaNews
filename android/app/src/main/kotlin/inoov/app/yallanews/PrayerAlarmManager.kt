package inoov.app.yallanews

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import org.json.JSONObject

/**
 * Native alarm manager that sets exact wake-up alarms for each prayer time.
 * Each alarm is keyed by a unique [requestCode] (date × prayer) so multiple
 * days' prayers can coexist without colliding.
 *
 * Alarms are persisted to SharedPreferences so [PrayerBootReceiver] can
 * restore them after device reboot, even when the app is not running.
 *
 * When the alarm fires, [PrayerNotificationReceiver] starts
 * [AdhanAudioService] which plays the adhan audio even when the app is
 * completely closed.
 */
object PrayerAlarmManager {

    const val ACTION_PRAYER_FIRE = "inoov.app.yallanews.PRAYER_NOTIFICATION_FIRE"
    const val ACTION_STOP_ADHAN = "inoov.app.yallanews.STOP_ADHAN"
    const val EXTRA_MUEZZIN = "muezzin_key"
    const val EXTRA_PRAYER_NAME = "prayer_name"
    const val EXTRA_REQUEST_CODE = "request_code"

    private const val PREFS_NAME = "prayer_alarms"
    private const val KEY_PREFIX = "alarm_"

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    /// Schedule an exact wake-up alarm for a prayer time and persist it for
    /// reboot restoration.
    fun schedulePrayerAlarm(
        context: Context,
        prayerTimeMillis: Long,
        prayerName: String,
        muezzin: String,
        requestCode: Int
    ) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(context, PrayerNotificationReceiver::class.java).apply {
            action = ACTION_PRAYER_FIRE
            putExtra(EXTRA_MUEZZIN, muezzin)
            putExtra(EXTRA_PRAYER_NAME, prayerName)
            putExtra(EXTRA_REQUEST_CODE, requestCode)
        }
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            requestCode,
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

        // Persist so the alarm survives device reboot.
        try {
            val json = JSONObject().put("time", prayerTimeMillis)
                .put("prayerName", prayerName)
                .put("muezzin", muezzin)
            prefs(context).edit().putString("$KEY_PREFIX$requestCode", json.toString()).apply()
        } catch (e: Exception) {
            android.util.Log.w("PrayerAlarmManager", "Failed to persist alarm $requestCode", e)
        }
    }

    /// Cancel a previously scheduled prayer alarm by request code.
    fun cancelPrayerAlarm(context: Context, requestCode: Int) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(context, PrayerNotificationReceiver::class.java).apply {
            action = ACTION_PRAYER_FIRE
        }
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        alarmManager.cancel(pendingIntent)
        prefs(context).edit().remove("$KEY_PREFIX$requestCode").apply()
    }

    /// Cancel all prayer alarms (legacy name-based codes and persisted
    /// request-code alarms) and clear persistence.
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
        val all = prefs(context).all
        for (key in all.keys) {
            if (!key.startsWith(KEY_PREFIX)) continue
            val code = key.removePrefix(KEY_PREFIX).toIntOrNull() ?: continue
            val intent = Intent(context, PrayerNotificationReceiver::class.java).apply {
                action = ACTION_PRAYER_FIRE
            }
            val pendingIntent = PendingIntent.getBroadcast(
                context, code, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            alarmManager.cancel(pendingIntent)
        }
        prefs(context).edit().clear().apply()
    }

    /// Return all persisted alarms for boot-time restoration.
    fun getStoredAlarms(context: Context): List<AlarmEntry> {
        val result = mutableListOf<AlarmEntry>()
        val all = prefs(context).all
        for (key in all.keys) {
            if (!key.startsWith(KEY_PREFIX)) continue
            val value = all[key] as? String ?: continue
            try {
                val json = JSONObject(value)
                result.add(
                    AlarmEntry(
                        requestCode = key.removePrefix(KEY_PREFIX).toIntOrNull() ?: -1,
                        prayerTimeMillis = json.optLong("time", 0),
                        prayerName = json.optString("prayerName", "Prayer"),
                        muezzin = json.optString("muezzin", "makkah"),
                    )
                )
            } catch (e: Exception) {
                android.util.Log.w("PrayerAlarmManager", "Failed to parse alarm $key", e)
            }
        }
        return result
    }

    data class AlarmEntry(
        val requestCode: Int,
        val prayerTimeMillis: Long,
        val prayerName: String,
        val muezzin: String,
    )
}
