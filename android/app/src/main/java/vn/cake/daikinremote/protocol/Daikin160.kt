package vn.cake.daikinremote.protocol

import vn.cake.daikinremote.ir.BitTiming
import vn.cake.daikinremote.ir.IrFrame
import vn.cake.daikinremote.ir.PulseBuilder
import java.time.LocalDateTime

/** Port of IRremoteESP8266 `IRDaikin160` (DAIKIN160, 160 bits / 20 bytes). */
class Daikin160State {
    val raw = bytesOf(
        0x11, 0xDA, 0x27, 0xF0, 0x0D, 0x00, 0x00,
        0x11, 0xDA, 0x27, 0x00, 0xD3, 0x30, 0x11, 0x00, 0x00, 0x1E, 0x0A, 0x08, 0x00,
    )

    fun setPower(on: Boolean) = raw.set(12, 0, 1, if (on) 1 else 0)
    fun setMode(code: Int) = raw.set(12, 4, 3, code)
    fun setTemp(c: Int) = raw.set(16, 1, 6, c.coerceIn(Daikin280State.MIN_TEMP, Daikin280State.MAX_TEMP) - 10)

    fun setFan(fan: Int) {
        val code = when {
            fan == 0xA || fan == 0xB -> fan
            fan < 1 || fan > 5 -> 0xA
            else -> 2 + fan
        }
        raw.set(17, 0, 4, code)
    }

    /** 1 (lowest) … 5 (highest), or 0xF for auto swing. */
    fun setSwingVertical(position: Int) = raw.set(13, 4, 4, if (position in 1..5) position else SWING_AUTO)

    fun finish(): ByteArray {
        raw.put(6, sumBytes(raw, 0, 6))
        raw.put(19, sumBytes(raw, 7, 12))
        return raw.copyOf()
    }

    companion object {
        const val SWING_LOWEST = 0x1
        const val SWING_AUTO = 0xF
        val TIMING = BitTiming(5000, 2145, 342, 1786, 700, 29650)

        fun send(data: ByteArray) = IrFrame(
            38000,
            PulseBuilder()
                .section(TIMING, data, 0, 7)
                .section(TIMING, data, 7, data.size - 7)
                .build(),
        )
    }
}

object Daikin160 : DaikinProtocol {
    override val id = "DAIKIN160"
    override val displayName = "Daikin160"
    override val remotes = "ARC423A5, FTE12HV2S"
    override val modes = ALL_MODES
    override val fans = ALL_FANS
    override val supportsSwingV = true
    override val supportsSwingH = false
    override val nativeTimer = false

    override fun tempRange(mode: Mode) = if (mode == Mode.HEAT) 10..30 else 18..32

    override fun encode(state: AcState, button: Button, now: LocalDateTime?): IrFrame {
        val ac = Daikin160State()
        ac.setPower(state.power)
        ac.setMode(state.mode.daikinCode())
        ac.setTemp(state.tempC)
        ac.setFan(state.fan.daikinCode())
        // No "off" position exists; swing off parks the vane at its reset (lowest) position.
        ac.setSwingVertical(if (state.swingV) Daikin160State.SWING_AUTO else Daikin160State.SWING_LOWEST)
        return Daikin160State.send(ac.finish())
    }
}
