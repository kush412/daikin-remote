package vn.cake.daikinremote.protocol

import vn.cake.daikinremote.ir.BitTiming
import vn.cake.daikinremote.ir.IrFrame
import vn.cake.daikinremote.ir.PulseBuilder
import java.time.LocalDateTime

/** Port of IRremoteESP8266 `IRDaikinESP` (DAIKIN, 280 bits / 35 bytes). */
class Daikin280State {
    val raw = ByteArray(LENGTH)

    init {
        reset()
    }

    fun reset() {
        raw.fill(0)
        raw.put(0, 0x11); raw.put(1, 0xDA); raw.put(2, 0x27); raw.put(4, 0xC5)
        raw.put(8, 0x11); raw.put(9, 0xDA); raw.put(10, 0x27); raw.put(12, 0x42)
        raw.put(16, 0x11); raw.put(17, 0xDA); raw.put(18, 0x27)
        raw.put(21, 0x49); raw.put(22, 0x1E); raw.put(24, 0xB0)
        raw.put(27, 0x06); raw.put(28, 0x60); raw.put(31, 0xC0)
        checksum()
    }

    fun setPower(on: Boolean) = raw.set(21, 0, 1, if (on) 1 else 0)

    /** One of the 3-bit Daikin mode codes. */
    fun setMode(code: Int) = raw.set(21, 4, 3, code)

    fun setTemp(c: Int) = raw.put(22, c.coerceIn(MIN_TEMP, MAX_TEMP) * 2)

    /** 1–5, or 0xA (auto) / 0xB (quiet). */
    fun setFan(fan: Int) {
        val code = when {
            fan == 0xA || fan == 0xB -> fan
            fan < 1 || fan > 5 -> 0xA
            else -> 2 + fan
        }
        raw.set(24, 4, 4, code)
    }

    fun setSwingVertical(on: Boolean) = raw.set(24, 0, 4, if (on) 0xF else 0)
    fun setSwingHorizontal(on: Boolean) = raw.set(25, 0, 4, if (on) 0xF else 0)

    fun setCurrentTime(minsSinceMidnight: Int) =
        raw.set(13, 0, 11, if (minsSinceMidnight > 24 * 60) 0 else minsSinceMidnight)

    fun setCurrentDay(day: Int) = raw.set(14, 3, 3, day)

    fun enableOnTimer(start: Int) { raw.set(21, 1, 1, 1); raw.set(26, 0, 12, start) }
    fun disableOnTimer() { raw.set(21, 1, 1, 0); raw.set(26, 0, 12, UNUSED_TIME) }
    fun enableOffTimer(end: Int) { raw.set(21, 2, 1, 1); raw.set(27, 4, 12, end) }
    fun disableOffTimer() { raw.set(21, 2, 1, 0); raw.set(27, 4, 12, UNUSED_TIME) }

    fun checksum() {
        raw.put(7, sumBytes(raw, 0, 7))
        raw.put(15, sumBytes(raw, 8, 7))
        raw.put(34, sumBytes(raw, 16, LENGTH - 16 - 1))
    }

    fun finish(): ByteArray {
        checksum()
        return raw.copyOf()
    }

    companion object {
        const val LENGTH = 35
        const val MIN_TEMP = 10
        const val MAX_TEMP = 32
        const val UNUSED_TIME = 0x600
        const val FREQ = 38000
        val TIMING = BitTiming(3650, 1623, 428, 1280, 428, 428 + 29000)

        fun send(data: ByteArray): IrFrame = IrFrame(
            FREQ,
            PulseBuilder()
                .zeroBits(TIMING, 5, TIMING.gap)
                .section(TIMING, data, 0, 8)
                .section(TIMING, data, 8, 8)
                .section(TIMING, data, 16, LENGTH - 16)
                .build(),
        )
    }
}

object Daikin280 : DaikinProtocol {
    override val id = "DAIKIN"
    override val displayName = "Daikin (280-bit)"
    override val remotes = "ARC433**, ARC470A1, ARC466A12/A33, ARC443A5 – most wall splits"
    override val modes = ALL_MODES
    override val fans = ALL_FANS
    override val supportsSwingV = true
    override val supportsSwingH = true
    override val nativeTimer = true

    override fun tempRange(mode: Mode) = if (mode == Mode.HEAT) 10..30 else 18..32

    override fun encode(state: AcState, button: Button, now: LocalDateTime?): IrFrame {
        val ac = Daikin280State()
        ac.setPower(state.power)
        ac.setMode(state.mode.daikinCode())
        when (state.mode) {
            // Real ARC remotes send 0xC0 in Dry and 25°C in Fan (see ir_Daikin.h).
            Mode.DRY -> ac.raw.put(22, 0xC0)
            Mode.FAN -> ac.setTemp(25)
            else -> ac.setTemp(state.tempC)
        }
        ac.setFan(state.fan.daikinCode())
        ac.setSwingVertical(state.swingV)
        ac.setSwingHorizontal(state.swingH)
        if (now != null) {
            ac.setCurrentTime(now.minutesOfDay)
            ac.setCurrentDay(now.daikinDay)
        }
        state.onTimerAt?.let { ac.enableOnTimer(minutesOfDay(it)) } ?: ac.disableOnTimer()
        state.offTimerAt?.let { ac.enableOffTimer(minutesOfDay(it)) } ?: ac.disableOffTimer()
        return Daikin280State.send(ac.finish())
    }
}
