package vn.cake.daikinremote.data

import vn.cake.daikinremote.ir.IrTransmitter
import vn.cake.daikinremote.protocol.AcState
import vn.cake.daikinremote.protocol.Button
import vn.cake.daikinremote.protocol.DaikinProtocol
import java.time.LocalDateTime

/** Timers that are run by the phone rather than encoded into the IR frame. */
fun Stored.usesPhoneTimer(protocol: DaikinProtocol) = phoneTimer || !protocol.nativeTimer

/** How late a phone timer may be before we treat it as missed (alarm blocked by the OS). */
const val MISSED_GRACE_MS = 2 * 60_000L

data class Settled(val state: AcState, val missed: List<String> = emptyList())

/**
 * Brings timers up to date at [nowMillis].
 * - AC-run timers: once due, the AC has switched itself, so the remote state follows and the
 *   timer is cleared (like a real remote's display).
 * - Phone-run timers: the receiver clears them when it fires. One still pending well past its
 *   time never fired, so it is cleared *without* changing power and reported as missed.
 */
fun AcState.settleTimers(phoneTimer: Boolean, nowMillis: Long = System.currentTimeMillis()): Settled {
    var s = this
    val missed = mutableListOf<String>()
    val due = listOfNotNull(onTimerAt?.let { it to true }, offTimerAt?.let { it to false })
        .sortedBy { it.first }
    for ((at, power) in due) {
        if (phoneTimer) {
            if (at + MISSED_GRACE_MS > nowMillis) continue
            missed += if (power) "ON" else "OFF"
        } else {
            if (at > nowMillis) continue
            s = s.copy(power = power)
        }
        s = if (power) s.copy(onTimerAt = null) else s.copy(offTimerAt = null)
    }
    return Settled(s, missed)
}

/** Encode and transmit; returns an error message or null. */
fun IrTransmitter.sendState(
    protocol: DaikinProtocol,
    state: AcState,
    button: Button,
    phoneTimer: Boolean,
): String? {
    // Phone-run timers must not also be programmed into the AC.
    val wire = if (phoneTimer) state.copy(onTimerAt = null, offTimerAt = null) else state
    return send(protocol.encode(wire, button, LocalDateTime.now()))
}
