package yukams.app.background_locator_2

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock

/**
 * Schedules the repeating liveness alarm.
 *
 * The location stream alone cannot guarantee presence: while the device is
 * stationary the fused provider may deliver nothing for hours, and the OS
 * power manager defers both GPS and network further once the device is idle.
 * This alarm wakes the app every [INTERVAL_MS] so the Dart background isolate
 * can POST a lightweight heartbeat (no location row, no GPS fix) that keeps
 * the family's "last seen" fresh.
 *
 * The alarm is deliberately inexact: a few minutes of drift is harmless for a
 * liveness signal, and inexact alarms avoid the exact-alarm special permission
 * introduced on newer Android versions. ELAPSED_REALTIME_WAKEUP is used so the
 * CPU wakes even in deep idle.
 */
object HeartbeatScheduler {
    /** How often the liveness alarm fires. 10 minutes keeps "last seen"
     *  comfortably fresher than any staleness threshold a viewer uses. */
    const val INTERVAL_MS: Long = 10 * 60 * 1000L

    private const val REQUEST_CODE = 4242

    fun schedule(context: Context) {
        val appContext = context.applicationContext
        val alarmManager =
            appContext.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pendingIntent = pendingIntent(appContext)
        val triggerAt = SystemClock.elapsedRealtime() + INTERVAL_MS
        // Re-scheduling with the same PendingIntent replaces the previous
        // registration, so start() may be called repeatedly without stacking
        // alarms.
        alarmManager.setInexactRepeating(
            AlarmManager.ELAPSED_REALTIME_WAKEUP,
            triggerAt,
            INTERVAL_MS,
            pendingIntent,
        )
    }

    fun cancel(context: Context) {
        val appContext = context.applicationContext
        val alarmManager =
            appContext.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarmManager.cancel(pendingIntent(appContext))
    }

    private fun pendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, HeartbeatReceiver::class.java)
            .setAction(Keys.ACTION_HEARTBEAT)
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            flags = flags or PendingIntent.FLAG_IMMUTABLE
        }
        return PendingIntent.getBroadcast(context, REQUEST_CODE, intent, flags)
    }
}
