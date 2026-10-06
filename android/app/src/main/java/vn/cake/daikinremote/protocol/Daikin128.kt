package vn.cake.daikinremote.protocol

import vn.cake.daikinremote.ir.BitTiming
import vn.cake.daikinremote.ir.IrFrame
import vn.cake.daikinremote.ir.PulseBuilder
import java.time.LocalDateTime

/** Mode/fan codes shared by DAIKIN128 and DAIKIN64. */
internal object Daikin128Codes {
    const val DRY = 0b0001
    const val COOL = 0b0010
    const val FAN = 0b0100
    const val HEAT = 0b1000
    const val AUTO = 0b1010

    const val FAN_AUTO = 0b0001
    const val FAN_HIGH = 0b0010
    const val FAN_MED = 0b0100
    const val FAN_LOW = 0b1000
    const val FAN_POWERFUL = 0b0011
    const val FAN_QUIET = 0b1001

    fun fan(f: Fan) = when (f) {
        Fan.AUTO -> FAN_AUTO
        Fan.QUIET -> FAN_QUIET
        Fan.L1, Fan.L2 -> FAN_LOW
        Fan.L3 -> FAN_MED
        Fan.L4, Fan.L5 -> FAN_HIGH
    }

    fun mode(m: Mode) = when (m) {
        Mode.AUTO -> AUTO
        Mode.COOL -> COOL
        Mode.DRY -> DRY
        Mode.HEAT -> HEAT
        Mode.FAN -> FAN
    }

    // Leader 2× (9800/9800), then header 4600/2500.
    const val LEADER = 9800
    val TIMING = BitTiming(4600, 2500, 350, 954, 382, 20300)
}

/** Port of IRremoteESP8266 `IRDaikin128` (DAIKIN128, 128 bits / 16 bytes). */
class Daikin128State {
    val raw = ByteArray(16).also { it.put(0, 0x16); it.put(7, 0x04); it.put(8, 0xA1) }

    private val mode get() = raw.get(1, 0, 4)

    /** The power bit means "toggle power". */
    fun setPowerToggle(toggle: Boolean) = raw.set(7, 3, 1, if (toggle) 1 else 0)

    fun setMode(code: Int) {
        val m = if (code in intArrayOf(Daikin128Codes.AUTO, Daikin128Codes.COOL, Daikin128Codes.HEAT,
                Daikin128Codes.FAN, Daikin128Codes.DRY)) code else Daikin128Codes.AUTO
        raw.set(1, 0, 4, m)
        setFan(raw.get(1, 4, 4)) // Quiet/Powerful depend on mode.
    }

    fun setTemp(c: Int) = raw.put(6, toBcd(c.coerceIn(MIN_TEMP, MAX_TEMP)))

    fun setFan(speed: Int) {
        var s = speed
        when (speed) {
            Daikin128Codes.FAN_QUIET, Daikin128Codes.FAN_POWERFUL ->
                if (mode == Daikin128Codes.AUTO) s = Daikin128Codes.FAN_AUTO
            Daikin128Codes.FAN_AUTO, Daikin128Codes.FAN_HIGH, Daikin128Codes.FAN_MED, Daikin128Codes.FAN_LOW -> Unit
            else -> s = Daikin128Codes.FAN_AUTO
        }
        raw.set(1, 4, 4, s)
    }

    fun setSwingVertical(on: Boolean) = raw.set(7, 0, 1, if (on) 1 else 0)

    fun setClock(mins: Int) {
        val m = if (mins >= 24 * 60) 0 else mins
        raw.put(3, toBcd(m / 60))
        raw.put(2, toBcd(m % 60))
    }

    fun setOnTimerEnabled(on: Boolean) = raw.set(4, 7, 1, if (on) 1 else 0)
    fun setOnTimer(mins: Int) = setTime(4, mins)
    fun setOffTimerEnabled(on: Boolean) = raw.set(5, 7, 1, if (on) 1 else 0)
    fun setOffTimer(mins: Int) = setTime(5, mins)

    private fun setTime(byte: Int, minsSinceMidnight: Int) {
        val mins = if (minsSinceMidnight >= 24 * 60) 0 else minsSinceMidnight
        raw.set(byte, 6, 1, if (mins % 60 >= 30) 1 else 0)
        raw.set(byte, 0, 6, toBcd(mins / 60))
    }

    fun finish(): ByteArray {
        raw.set(7, 4, 4, sumNibbles(raw, 0, 7, raw.u(7) and 0x0F) and 0x0F)
        raw.put(15, sumNibbles(raw, 8, 7))
        return raw.copyOf()
    }

    companion object {
        const val MIN_TEMP = 16
        const val MAX_TEMP = 30

        fun send(data: ByteArray): IrFrame {
            val t = Daikin128Codes.TIMING
            return IrFrame(
                38000,
                PulseBuilder()
                    .mark(Daikin128Codes.LEADER).space(Daikin128Codes.LEADER)
                    .mark(Daikin128Codes.LEADER).space(Daikin128Codes.LEADER)
                    .section(t, data, 0, 8)
                    .section(t, data, 8, 8, hdrMark = 0, hdrSpace = 0, footerMark = t.hdrMark)
                    .build(),
            )
        }
    }
}

object Daikin128 : DaikinProtocol {
    override val id = "DAIKIN128"
    override val displayName = "Daikin128"
    override val remotes = "BRC52B63, 17 Series FTXB**AXVJU"
    override val modes = ALL_MODES
    override val fans = listOf(Fan.AUTO, Fan.QUIET, Fan.L1, Fan.L3, Fan.L5)
    override val supportsSwingV = true
    override val supportsSwingH = false
    override val nativeTimer = true
    override val powerIsToggle = true

    override fun tempRange(mode: Mode) = Daikin128State.MIN_TEMP..Daikin128State.MAX_TEMP

    override fun encode(state: AcState, button: Button, now: LocalDateTime?): IrFrame {
        val ac = Daikin128State()
        ac.setPowerToggle(button == Button.POWER)
        ac.setMode(Daikin128Codes.mode(state.mode))
        ac.setTemp(state.tempC)
        ac.setFan(Daikin128Codes.fan(state.fan))
        ac.setSwingVertical(state.swingV)
        now?.let { ac.setClock(it.minutesOfDay) }
        ac.setOnTimerEnabled(state.onTimerAt != null)
        state.onTimerAt?.let { ac.setOnTimer(minutesOfDay(it)) }
        ac.setOffTimerEnabled(state.offTimerAt != null)
        state.offTimerAt?.let { ac.setOffTimer(minutesOfDay(it)) }
        return Daikin128State.send(ac.finish())
    }
}
