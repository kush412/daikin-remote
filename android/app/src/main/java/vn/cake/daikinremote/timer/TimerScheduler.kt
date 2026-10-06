package vn.cake.daikinremote.timer

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import vn.cake.daikinremote.MainActivity

/**
 * Phone-side on/off timers. Uses alarm-clock alarms (exact, exempt from Doze) to wake the
 * device, and a foreground service to keep the process alive while a timer is pending, because
 * Xiaomi/HyperOS and similar ROMs won't start a killed app to deliver an alarm.
 */
object TimerScheduler {
    const val EXTRA_POWER = "power"

    fun sync(context: Context, onAt: Long?, offAt: Long?) {
        set(context, power = true, at = onAt)
        set(context, power = false, at = offAt)
        if (onAt != null || offAt != null) TimerService.start(context) else TimerService.stop(context)
    }

    fun cancelAll(context: Context) = sync(context, null, null)

    private fun set(context: Context, power: Boolean, at: Long?) {
        val alarms = context.getSystemService(AlarmManager::class.java)
        val pi = firePendingIntent(context, power)
        alarms.cancel(pi)
        if (at == null) return
        val canExact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarms.canScheduleExactAlarms()
        if (canExact) {
            alarms.setAlarmClock(AlarmManager.AlarmClockInfo(at, showPendingIntent(context)), pi)
        } else {
            alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
        }
    }

    private fun firePendingIntent(context: Context, power: Boolean): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            if (power) 1 else 2,
            Intent(context, TimerReceiver::class.java).putExtra(EXTRA_POWER, power),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    fun showPendingIntent(context: Context): PendingIntent =
        PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
}
