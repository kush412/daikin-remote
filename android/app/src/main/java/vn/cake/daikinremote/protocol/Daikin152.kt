package vn.cake.daikinremote.protocol

import vn.cake.daikinremote.ir.BitTiming
import vn.cake.daikinremote.ir.IrFrame
import vn.cake.daikinremote.ir.PulseBuilder
import java.time.LocalDateTime
import java.time.ZoneId

/** Port of IRremoteESP8266 `IRDaikin152` (DAIKIN152, 152 bits / 19 bytes). */
class Daikin152State {
    val raw = ByteArray(LENGTH).also {
        it.put(0, 0x11); it.put(1, 0xDA); it.put(2, 0x27); it.put(15, 0xC5)
    }

    private val mode get() = raw.get(5, 4, 3)

    fun setPower(on: Boolean) = raw.set(5, 0, 1, if (on) 1 else 0)

    fun setMode(code: Int) {
        when (code) {
            0b110 -> setTemp(FAN_TEMP) // Fan mode uses a special temperature.
            0b010 -> setTemp(Daikin2State.MIN_COOL_TEMP) // Dry is fixed at 18°C.
            0b000, 0b011, 0b100 -> Unit
            else -> { raw.set(5, 4, 3, 0); return }
        }
        raw.set(5, 4, 3, code)
    }

    fun setTemp(c: Int) {
        val min = if (mode == 0b100) Daikin280State.MIN_TEMP else Daikin2State.MIN_COOL_TEMP
        val degrees = if (c == FAN_TEMP) c else c.coerceIn(min, Daikin280State.MAX_TEMP)
        raw.set(6, 1, 7, degrees)
    }

    fun setFan(fan: Int) {
        val code = when {
            fan == 0xA || fan == 0xB -> fan
            fan < 1 || fan > 5 -> 0xA
            else -> 2 + fan
        }
        raw.set(8, 4, 4, code)
    }

    fun setSwingV(on: Boolean) = raw.set(8, 0, 4, if (on) 0xF else 0)

    // Timers: not in IRremoteESP8266. The frame matches section 3 of DAIKIN280 (and section 2 of
    // DAIKIN2), whose timer fields sit at the same offsets; a real ARC480A5 "night sleep" capture
    // (issue #873) carries 0x3C (60) there. With no clock in this protocol, the value is the
    // number of minutes from now. Unused timers are sent as 0, as the real remote does.
    fun enableOnTimer(minutesFromNow: Int) {
        raw.set(5, 1, 1, 1)
        raw.set(10, 0, 12, minutesFromNow.coerceIn(1, MAX_TIMER_MINUTES))
    }

    fun enableOffTimer(minutesFromNow: Int) {
        raw.set(5, 2, 1, 1)
        raw.set(11, 4, 12, minutesFromNow.coerceIn(1, MAX_TIMER_MINUTES))
    }

    fun finish(): ByteArray {
        raw.put(LENGTH - 1, sumBytes(raw, 0, LENGTH - 1))
        return raw.copyOf()
    }

    companion object {
        const val LENGTH = 19
        const val FAN_TEMP = 0x60
        const val MAX_TIMER_MINUTES = 12 * 60
        val TIMING = BitTiming(3492, 1718, 433, 1529, 433, 25182)

        fun send(data: ByteArray) = IrFrame(
            38000,
            PulseBuilder()
                .zeroBits(TIMING, 5, TIMING.gap)
                .section(TIMING, data)
                .build(),
        )
    }
}

object Daikin152 : DaikinProtocol {
    override val id = "DAIKIN152"
    override val displayName = "Daikin152"
    override val remotes = "ARC480A5, ARC480A93 (timer support is reverse-engineered)"
    override val modes = ALL_MODES
    override val fans = ALL_FANS
    override val supportsSwingV = true
    override val supportsSwingH = false
    override val nativeTimer = true

    override fun tempRange(mode: Mode) = if (mode == Mode.HEAT) 10..30 else 18..32

    override fun encode(state: AcState, button: Button, now: LocalDateTime?): IrFrame {
        val ac = Daikin152State()
        ac.setPower(state.power)
        // Temp before mode, so Dry/Fan can override it with their fixed values.
        ac.setTemp(state.tempC)
        ac.setMode(state.mode.daikinCode())
        if (state.mode == Mode.AUTO || state.mode == Mode.COOL || state.mode == Mode.HEAT) ac.setTemp(state.tempC)
        ac.setFan(state.fan.daikinCode())
        ac.setSwingV(state.swingV)
        // Relative timers: re-sent with the remaining minutes on every press, like the remote.
        val nowMs = now?.atZone(ZoneId.systemDefault())?.toInstant()?.toEpochMilli() ?: System.currentTimeMillis()
        state.onTimerAt?.let { ac.enableOnTimer(minutesUntil(it, nowMs)) }
        state.offTimerAt?.let { ac.enableOffTimer(minutesUntil(it, nowMs)) }
        return Daikin152State.send(ac.finish())
    }
}
