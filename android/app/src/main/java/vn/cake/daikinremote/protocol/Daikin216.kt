package vn.cake.daikinremote.protocol

import vn.cake.daikinremote.ir.BitTiming
import vn.cake.daikinremote.ir.IrFrame
import vn.cake.daikinremote.ir.PulseBuilder
import java.time.LocalDateTime

/** Port of IRremoteESP8266 `IRDaikin216` (DAIKIN216, 216 bits / 27 bytes). */
class Daikin216State {
    val raw = ByteArray(LENGTH)

    init {
        raw.put(0, 0x11); raw.put(1, 0xDA); raw.put(2, 0x27); raw.put(3, 0xF0)
        raw.put(8, 0x11); raw.put(9, 0xDA); raw.put(10, 0x27); raw.put(23, 0xC0)
    }

    fun setPower(on: Boolean) = raw.set(13, 0, 1, if (on) 1 else 0)
    fun setMode(code: Int) = raw.set(13, 4, 3, code)
    fun setTemp(c: Int) = raw.set(14, 1, 6, c.coerceIn(Daikin280State.MIN_TEMP, Daikin280State.MAX_TEMP))

    fun setFan(fan: Int) {
        val code = when {
            fan == 0xA || fan == 0xB -> fan
            fan < 1 || fan > 5 -> 0xA
            else -> 2 + fan
        }
        raw.set(16, 4, 4, code)
    }

    fun setSwingVertical(on: Boolean) = raw.set(16, 0, 4, if (on) 0xF else 0)
    fun setSwingHorizontal(on: Boolean) = raw.set(17, 0, 4, if (on) 0xF else 0)

    fun finish(): ByteArray {
        raw.put(7, sumBytes(raw, 0, 7))
        raw.put(26, sumBytes(raw, 8, LENGTH - 8 - 1))
        return raw.copyOf()
    }

    companion object {
        const val LENGTH = 27
        val TIMING = BitTiming(3440, 1750, 420, 1300, 450, 29650)

        fun send(data: ByteArray) = IrFrame(
            38000,
            PulseBuilder()
                .section(TIMING, data, 0, 8)
                .section(TIMING, data, 8, LENGTH - 8)
                .build(),
        )
    }
}

object Daikin216 : DaikinProtocol {
    override val id = "DAIKIN216"
    override val displayName = "Daikin216"
    override val remotes = "ARC433B69, ARC484A4, FTQ60TV16U2"
    override val modes = ALL_MODES
    override val fans = ALL_FANS
    override val supportsSwingV = true
    override val supportsSwingH = true
    override val nativeTimer = false

    override fun tempRange(mode: Mode) = if (mode == Mode.HEAT) 10..30 else 18..32

    override fun encode(state: AcState, button: Button, now: LocalDateTime?): IrFrame {
        val ac = Daikin216State()
        ac.setPower(state.power)
        ac.setMode(state.mode.daikinCode())
        ac.setTemp(state.tempC)
        ac.setFan(state.fan.daikinCode())
        ac.setSwingVertical(state.swingV)
        ac.setSwingHorizontal(state.swingH)
        return Daikin216State.send(ac.finish())
    }
}
