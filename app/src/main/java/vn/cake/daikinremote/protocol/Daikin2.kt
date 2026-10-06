package vn.cake.daikinremote.protocol

import vn.cake.daikinremote.ir.BitTiming
import vn.cake.daikinremote.ir.IrFrame
import vn.cake.daikinremote.ir.PulseBuilder
import java.time.LocalDateTime

/** Port of IRremoteESP8266 `IRDaikin2` (DAIKIN2, 312 bits / 39 bytes). */
class Daikin2State {
    val raw = ByteArray(LENGTH)

    init {
        reset()
    }

    fun reset() {
        raw.fill(0)
        intArrayOf(
            0x11, 0xDA, 0x27, 0x00, 0x01, 0x00, 0xC0, 0x70, 0x08, 0x0C,
            0x80, 0x04, 0xB0, 0x16, 0x24, 0x00, 0x00, 0xBE, 0xD0, 0x00,
            0x11, 0xDA, 0x27, 0x00, 0x00, 0x08, 0x00, 0x00, 0xA0, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0xC1, 0x80, 0x60, 0x00,
        ).forEachIndexed { i, v -> raw.put(i, v) }
        disableOnTimer()
        disableOffTimer()
        checksum()
    }

    private val mode get() = raw.get(25, 4, 3)
    private val temp get() = raw.get(26, 1, 6)

    fun setPower(on: Boolean) {
        raw.set(25, 0, 1, if (on) 1 else 0)
        raw.set(6, 7, 1, if (on) 0 else 1) // Power2
    }

    fun setMode(code: Int) {
        val m = if (code in intArrayOf(0b011, 0b100, 0b110, 0b010)) code else 0
        raw.set(25, 4, 3, m)
        if (m == 0b011) setTemp(temp) // Cool has a different minimum temperature.
    }

    fun setTemp(c: Int) {
        val min = if (mode == 0b011) MIN_COOL_TEMP else Daikin280State.MIN_TEMP
        raw.set(26, 1, 6, c.coerceIn(min, Daikin280State.MAX_TEMP))
    }

    fun setFan(fan: Int) {
        val code = when {
            fan == 0xA || fan == 0xB -> fan
            fan < 1 || fan > 5 -> 0xA
            else -> 2 + fan
        }
        raw.set(28, 4, 4, code)
    }

    fun setSwingVertical(position: Int) = raw.set(18, 0, 4, position)
    fun setSwingHorizontal(position: Int) = raw.put(17, position)

    fun setCurrentTime(mins: Int) = raw.set(5, 0, 12, if (mins > 24 * 60) 0 else mins)

    fun enableOnTimer(start: Int) {
        raw.set(36, 5, 1, 0) // SleepTimer
        raw.set(25, 1, 1, 1)
        raw.set(30, 0, 12, start)
    }

    fun disableOnTimer() {
        raw.set(30, 0, 12, Daikin280State.UNUSED_TIME)
        raw.set(25, 1, 1, 0)
        raw.set(36, 5, 1, 0)
    }

    fun enableOffTimer(end: Int) { raw.set(25, 2, 1, 1); raw.set(31, 4, 12, end) }
    fun disableOffTimer() { raw.set(31, 4, 12, Daikin280State.UNUSED_TIME); raw.set(25, 2, 1, 0) }

    fun setBeep(beep: Int) = raw.set(7, 6, 2, beep)
    fun setLight(light: Int) = raw.set(7, 4, 2, light)
    fun setMold(on: Boolean) = raw.set(8, 3, 1, if (on) 1 else 0)
    fun setClean(on: Boolean) = raw.set(8, 5, 1, if (on) 1 else 0)

    fun checksum() {
        raw.put(19, sumBytes(raw, 0, 19))
        raw.put(38, sumBytes(raw, 20, 18))
    }

    fun finish(): ByteArray {
        checksum()
        return raw.copyOf()
    }

    companion object {
        const val LENGTH = 39
        const val MIN_COOL_TEMP = 18
        const val SWING_V_AUTO = 0xF
        const val SWING_V_OFF = 0xE
        const val SWING_H_AUTO = 0xBE
        const val SWING_H_OFF = 0xBF
        const val FREQ = 36700
        private const val LEADER_MARK = 10024
        private const val LEADER_SPACE = 25180
        val TIMING = BitTiming(3500, 1728, 460, 1270, 420, LEADER_MARK + LEADER_SPACE)

        fun send(data: ByteArray) = IrFrame(
            FREQ,
            PulseBuilder()
                .mark(LEADER_MARK).space(LEADER_SPACE)
                .section(TIMING, data, 0, 20)
                .section(TIMING, data, 20, LENGTH - 20)
                .build(),
        )
    }
}

object Daikin2 : DaikinProtocol {
    override val id = "DAIKIN2"
    override val displayName = "Daikin2 (312-bit)"
    override val remotes = "ARC477A1, FTXZ**NV1B"
    override val modes = ALL_MODES
    override val fans = ALL_FANS
    override val supportsSwingV = true
    override val supportsSwingH = true
    override val nativeTimer = true

    override fun tempRange(mode: Mode) = if (mode == Mode.HEAT) 10..30 else 18..32

    override fun encode(state: AcState, button: Button, now: LocalDateTime?): IrFrame {
        val ac = Daikin2State()
        ac.setPower(state.power)
        ac.setMode(state.mode.daikinCode())
        ac.setTemp(state.tempC)
        ac.setFan(state.fan.daikinCode())
        ac.setSwingVertical(if (state.swingV) Daikin2State.SWING_V_AUTO else Daikin2State.SWING_V_OFF)
        ac.setSwingHorizontal(if (state.swingH) Daikin2State.SWING_H_AUTO else Daikin2State.SWING_H_OFF)
        now?.let { ac.setCurrentTime(it.minutesOfDay) }
        state.onTimerAt?.let { ac.enableOnTimer(minutesOfDay(it)) } ?: ac.disableOnTimer()
        state.offTimerAt?.let { ac.enableOffTimer(minutesOfDay(it)) } ?: ac.disableOffTimer()
        return Daikin2State.send(ac.finish())
    }
}
