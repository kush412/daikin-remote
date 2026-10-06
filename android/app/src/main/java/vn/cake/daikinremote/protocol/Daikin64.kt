package vn.cake.daikinremote.protocol

import vn.cake.daikinremote.ir.IrFrame
import vn.cake.daikinremote.ir.PulseBuilder
import java.time.LocalDateTime

/**
 * Port of IRremoteESP8266 `IRDaikin64` (DAIKIN64, 64 bits). Held as 8 little-endian bytes,
 * which is exactly the LSB-first order the 64-bit value is transmitted in.
 */
class Daikin64State {
    // kDaikin64KnownGoodState = 0x7C16161607204216
    val raw = bytesOf(0x16, 0x42, 0x20, 0x07, 0x16, 0x16, 0x16, 0x7C)

    fun setPowerToggle(toggle: Boolean) = raw.set(7, 3, 1, if (toggle) 1 else 0)

    fun setMode(code: Int) = raw.set(
        1, 0, 4,
        if (code in intArrayOf(Daikin128Codes.FAN, Daikin128Codes.DRY, Daikin128Codes.COOL, Daikin128Codes.HEAT)) code
        else Daikin128Codes.COOL,
    )

    fun setTemp(c: Int) = raw.put(6, toBcd(c.coerceIn(Daikin128State.MIN_TEMP, Daikin128State.MAX_TEMP)))

    fun setFan(speed: Int) = raw.set(1, 4, 4, speed)

    fun setSwingVertical(on: Boolean) = raw.set(7, 0, 1, if (on) 1 else 0)

    fun setClock(mins: Int) {
        val m = if (mins >= 24 * 60) 0 else mins
        raw.put(2, toBcd(m % 60))
        raw.put(3, toBcd(m / 60))
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
        // Sum of the 15 nibbles below the checksum nibble.
        val sum = sumNibbles(raw, 0, 7, raw.u(7) and 0x0F) and 0x0F
        raw.set(7, 4, 4, sum)
        return raw.copyOf()
    }

    fun toLong(): Long = raw.foldIndexed(0L) { i, acc, b -> acc or ((b.toLong() and 0xFF) shl (8 * i)) }

    companion object {
        fun send(data: ByteArray): IrFrame {
            val t = Daikin128Codes.TIMING
            return IrFrame(
                38000,
                PulseBuilder()
                    .mark(Daikin128Codes.LEADER).space(Daikin128Codes.LEADER)
                    .mark(Daikin128Codes.LEADER).space(Daikin128Codes.LEADER)
                    .section(t, data)
                    .mark(t.hdrMark).space(100_000)
                    .build(),
            )
        }
    }
}

object Daikin64 : DaikinProtocol {
    override val id = "DAIKIN64"
    override val displayName = "Daikin64"
    override val remotes = "DGS01, BRC4C158, FFN-C/FCN-F, FTWX35AXV1"
    override val modes = listOf(Mode.COOL, Mode.DRY, Mode.HEAT, Mode.FAN)
    override val fans = listOf(Fan.AUTO, Fan.QUIET, Fan.L1, Fan.L3, Fan.L5)
    override val supportsSwingV = true
    override val supportsSwingH = false
    override val nativeTimer = true
    override val powerIsToggle = true

    override fun tempRange(mode: Mode) = Daikin128State.MIN_TEMP..Daikin128State.MAX_TEMP

    override fun encode(state: AcState, button: Button, now: LocalDateTime?): IrFrame {
        val ac = Daikin64State()
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
        return Daikin64State.send(ac.finish())
    }
}
