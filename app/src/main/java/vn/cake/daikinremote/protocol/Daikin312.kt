package vn.cake.daikinremote.protocol

import vn.cake.daikinremote.ir.BitTiming
import vn.cake.daikinremote.ir.IrFrame
import vn.cake.daikinremote.ir.PulseBuilder
import java.time.LocalDateTime

/** Port of IRremoteESP8266 `IRDaikin312` (DAIKIN312, 312 bits / 39 bytes). */
class Daikin312State {
    val raw = ByteArray(LENGTH)

    init {
        reset()
    }

    fun reset() {
        intArrayOf(
            0x11, 0xDA, 0x27, 0x00, 0x02, 0x58, 0x64, 0x00, 0x64, 0x00,
            0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x11, 0xDA, 0x27, 0x00, 0x00, 0x08, 0x2C, 0x00, 0x00, 0x00,
            0x00, 0x06, 0x60, 0x00, 0x00, 0xC5, 0x00, 0x08, 0x00,
        ).forEachIndexed { i, v -> raw.put(i, v) }
        disableOnTimer()
        disableOffTimer()
        checksum()
    }

    private val mode get() = raw.get(25, 4, 3)
    private val tempC get() = raw.get(26, 0, 7) / 2

    fun setPower(on: Boolean) {
        raw.set(25, 0, 1, if (on) 1 else 0)
        raw.set(6, 7, 1, if (on) 0 else 1) // Power2
    }

    fun setMode(code: Int) {
        val m = if (code in intArrayOf(0b011, 0b100, 0b110, 0b010)) code else 0
        raw.set(25, 4, 3, m)
        if (m == 0b011) setTemp(tempC)
    }

    fun setTemp(c: Int) {
        val min = if (mode == 0b011) Daikin2State.MIN_COOL_TEMP else Daikin280State.MIN_TEMP
        raw.set(26, 0, 7, c.coerceIn(min, Daikin280State.MAX_TEMP) * 2)
    }

    fun setFan(fan: Int) {
        val code = when {
            fan == 0xA || fan == 0xB -> fan
            fan < 1 || fan > 5 -> 0xA
            else -> 2 + fan
        }
        raw.set(28, 4, 4, code)
    }

    fun setSwingVertical(position: Int) = raw.set(28, 0, 4, position)
    fun setSwingHorizontal(position: Int) = raw.set(29, 0, 4, position)

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
        const val SWING_AUTO = 0xF
        const val SWING_OFF = 0x0
        const val FREQ = 36700
        private const val HDR_GAP = 25100
        val TIMING = BitTiming(3518, 1688, 453, 1275, 414, 35512)

        fun send(data: ByteArray) = IrFrame(
            FREQ,
            PulseBuilder()
                .zeroBits(TIMING, 5, HDR_GAP)
                .section(TIMING, data, 0, 20)
                .section(TIMING, data, 20, LENGTH - 20)
                .build(),
        )
    }
}

object Daikin312 : DaikinProtocol {
    override val id = "DAIKIN312"
    override val displayName = "Daikin312"
    override val remotes = "ARC466A58, ARC466A67, ARC472A43, FTXM20R5V1B"
    override val modes = ALL_MODES
    override val fans = ALL_FANS
    override val supportsSwingV = true
    override val supportsSwingH = true
    override val nativeTimer = true

    override fun tempRange(mode: Mode) = if (mode == Mode.HEAT) 10..30 else 18..32

    override fun encode(state: AcState, button: Button, now: LocalDateTime?): IrFrame {
        val ac = Daikin312State()
        ac.setPower(state.power)
        ac.setMode(state.mode.daikinCode())
        ac.setTemp(state.tempC)
        ac.setFan(state.fan.daikinCode())
        ac.setSwingVertical(if (state.swingV) Daikin312State.SWING_AUTO else Daikin312State.SWING_OFF)
        ac.setSwingHorizontal(if (state.swingH) Daikin312State.SWING_AUTO else Daikin312State.SWING_OFF)
        now?.let { ac.setCurrentTime(it.minutesOfDay) }
        state.onTimerAt?.let { ac.enableOnTimer(minutesOfDay(it)) } ?: ac.disableOnTimer()
        state.offTimerAt?.let { ac.enableOffTimer(minutesOfDay(it)) } ?: ac.disableOffTimer()
        return Daikin312State.send(ac.finish())
    }
}
