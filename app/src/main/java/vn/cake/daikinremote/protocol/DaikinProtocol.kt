package vn.cake.daikinremote.protocol

import vn.cake.daikinremote.ir.IrFrame
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId

interface DaikinProtocol {
    val id: String
    val displayName: String
    /** Remote / AC models known to use this protocol. */
    val remotes: String
    val modes: List<Mode>
    val fans: List<Fan>
    val supportsSwingV: Boolean
    val supportsSwingH: Boolean
    /** True if the AC itself runs the on/off timer; otherwise the phone has to send it later. */
    val nativeTimer: Boolean
    /** True if the power bit means "toggle" rather than an absolute on/off. */
    val powerIsToggle: Boolean get() = false

    fun tempRange(mode: Mode): IntRange

    /**
     * Encode the full [state]. [now] is the phone's local time, used for the clock and timer
     * fields; null leaves them at their reset values (the golden tests rely on that).
     */
    fun encode(state: AcState, button: Button, now: LocalDateTime?): IrFrame
}

/** Minutes since local midnight of an epoch-millis instant. */
internal fun minutesOfDay(epochMillis: Long): Int {
    val t = Instant.ofEpochMilli(epochMillis).atZone(ZoneId.systemDefault()).toLocalTime()
    return t.hour * 60 + t.minute
}

/** Whole minutes from [nowMillis] until [atMillis], rounded up. */
internal fun minutesUntil(atMillis: Long, nowMillis: Long): Int = ((atMillis - nowMillis + 59_999) / 60_000).toInt()

internal val LocalDateTime.minutesOfDay: Int get() = hour * 60 + minute

/** Daikin day-of-week: SUN=1 … SAT=7. */
internal val LocalDateTime.daikinDay: Int get() = dayOfWeek.value % 7 + 1

/** The value the ported `setFan()` setters take: 1–5, or 0xA (auto) / 0xB (quiet). */
internal fun Fan.daikinCode(): Int = when (this) {
    Fan.AUTO -> 0xA
    Fan.QUIET -> 0xB
    else -> level
}

/** Daikin 3-bit mode codes shared by most protocols. */
internal fun Mode.daikinCode(): Int = when (this) {
    Mode.AUTO -> 0b000
    Mode.DRY -> 0b010
    Mode.COOL -> 0b011
    Mode.HEAT -> 0b100
    Mode.FAN -> 0b110
}

internal val ALL_MODES = Mode.entries.toList()
internal val ALL_FANS = Fan.entries.toList()
