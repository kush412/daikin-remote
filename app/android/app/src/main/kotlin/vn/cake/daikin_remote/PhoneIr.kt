package vn.cake.daikin_remote

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.hardware.ConsumerIrManager
import android.os.Build
import kotlin.math.abs

/** The phone's built-in IR blaster. */
object PhoneIr {
    private fun manager(context: Context) =
        context.getSystemService(Context.CONSUMER_IR_SERVICE) as ConsumerIrManager?

    fun hasEmitter(context: Context): Boolean = manager(context)?.hasIrEmitter() == true

    /** Returns null on success, or an error message. */
    fun transmit(context: Context, frequency: Int, pattern: IntArray): String? {
        val ir = manager(context) ?: return "No IR service on this device"
        if (!ir.hasIrEmitter()) return "This phone has no IR blaster"
        // A trailing space carries no information, so the pattern ends on a mark.
        val p = if (pattern.size % 2 == 0) pattern.copyOf(pattern.size - 1) else pattern
        return try {
            ir.transmit(closestFrequency(ir, frequency), p)
            null
        } catch (e: Exception) {
            e.message ?: e.javaClass.simpleName
        }
    }

    private fun closestFrequency(ir: ConsumerIrManager, wanted: Int): Int {
        val ranges = ir.carrierFrequencies ?: return wanted
        if (ranges.isEmpty() || ranges.any { wanted in it.minFrequency..it.maxFrequency }) return wanted
        return ranges.map { wanted.coerceIn(it.minFrequency, it.maxFrequency) }.minBy { abs(it - wanted) }
    }
}

/**
 * Phone-run on/off timers, mirroring the Wi-Fi bridge's: Dart hands over the finished frame,
 * it is stored with the fire time, and an alarm-clock alarm (exact, exempt from Doze) sends it.
 * No Dart code runs in the background.
 */
object IrTimers {
    private const val PREFS = "ir_timers"
    /** How late an alarm may be before we treat it as blocked by the OS. */
    private const val MISSED_GRACE_MS = 2 * 60_000L
    val SLOTS = listOf("on", "off")

    fun set(context: Context, slot: String, seconds: Long, freq: Int, pattern: IntArray) {
        val at = System.currentTimeMillis() + seconds * 1000
        prefs(context).edit()
            .putLong("${slot}_at", at)
            .putInt("${slot}_freq", freq)
            .putString("${slot}_pattern", pattern.joinToString(","))
            .apply()
        arm(context, slot, at)
    }

    fun cancel(context: Context, slot: String) {
        alarms(context).cancel(firePendingIntent(context, slot))
        clear(context, slot)
    }

    /**
     * Seconds until each slot fires (-1 if none), plus slots whose alarm never fired (the ROM
     * blocked it); those are reported once and cleared.
     */
    fun status(context: Context): Map<String, Any> {
        val now = System.currentTimeMillis()
        val out = HashMap<String, Any>()
        val missed = ArrayList<String>()
        for (slot in SLOTS) {
            val at = prefs(context).getLong("${slot}_at", 0)
            when {
                at == 0L -> out[slot] = -1
                at + MISSED_GRACE_MS < now -> {
                    missed += slot
                    clear(context, slot)
                    out[slot] = -1
                }
                else -> out[slot] = ((at - now + 999) / 1000).coerceAtLeast(0).toInt()
            }
        }
        out["missed"] = missed
        return out
    }

    /** Sends the stored frame for [slot] and clears it. */
    fun fire(context: Context, slot: String) {
        val p = prefs(context)
        val freq = p.getInt("${slot}_freq", 0)
        val pattern = p.getString("${slot}_pattern", null)
        clear(context, slot)
        if (freq == 0 || pattern.isNullOrEmpty()) return
        PhoneIr.transmit(context, freq, pattern.split(',').map { it.toInt() }.toIntArray())
    }

    /** Alarms don't survive a reboot. */
    fun rearm(context: Context) {
        val now = System.currentTimeMillis()
        for (slot in SLOTS) {
            val at = prefs(context).getLong("${slot}_at", 0)
            if (at > now) arm(context, slot, at)
        }
    }

    private fun arm(context: Context, slot: String, at: Long) {
        val alarms = alarms(context)
        val pi = firePendingIntent(context, slot)
        alarms.cancel(pi)
        val canExact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarms.canScheduleExactAlarms()
        if (canExact) {
            alarms.setAlarmClock(AlarmManager.AlarmClockInfo(at, showPendingIntent(context)), pi)
        } else {
            alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
        }
    }

    private fun clear(context: Context, slot: String) {
        prefs(context).edit().remove("${slot}_at").remove("${slot}_freq").remove("${slot}_pattern").apply()
    }

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun alarms(context: Context) = context.getSystemService(AlarmManager::class.java)

    private fun firePendingIntent(context: Context, slot: String): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            if (slot == "on") 1 else 2,
            Intent(context, IrTimerReceiver::class.java).putExtra("slot", slot),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    private fun showPendingIntent(context: Context): PendingIntent =
        PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
}

class IrTimerReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        IrTimers.fire(context, intent.getStringExtra("slot") ?: return)
    }
}

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) IrTimers.rearm(context)
    }
}
