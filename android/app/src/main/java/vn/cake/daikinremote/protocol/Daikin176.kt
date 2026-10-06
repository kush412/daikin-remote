package vn.cake.daikinremote.protocol

import vn.cake.daikinremote.ir.BitTiming
import vn.cake.daikinremote.ir.IrFrame
import vn.cake.daikinremote.ir.PulseBuilder
import java.time.LocalDateTime

/** Port of IRremoteESP8266 `IRDaikin176` (DAIKIN176, 176 bits / 22 bytes). */
class Daikin176State {
    val raw = bytesOf(
        0x11, 0xDA, 0x17, 0x18, 0x04, 0x00, 0x00,
        0x11, 0xDA, 0x17, 0x18, 0x00, 0x73, 0x00, 0x20, 0x00, 0x00, 0x00, 0x16, 0x00, 0x20, 0x00,
    )
    private var savedTemp = raw.get(17, 1, 6) + 9

    private val mode get() = raw.get(14, 4, 3)

    fun setPower(on: Boolean) {
        raw.put(13, 0) // ModeButton
        raw.set(14, 0, 1, if (on) 1 else 0)
    }

    fun setMode(code: Int) {
        var m = code
        val alt = when (code) {
            DRY -> 2
            FAN -> 6
            AUTO, COOL, HEAT -> 7
            else -> { m = COOL; 7 }
        }
        raw.set(14, 4, 3, m)
        raw.set(12, 4, 3, alt)
        setTemp(savedTemp)
        raw.put(13, MODE_BUTTON) // Must follow setTemp(), which clears it.
    }

    fun setTemp(c: Int) {
        var degrees = c.coerceIn(Daikin280State.MIN_TEMP, Daikin280State.MAX_TEMP)
        savedTemp = degrees
        if (mode == DRY || mode == FAN) degrees = DRY_FAN_TEMP
        raw.set(17, 1, 6, degrees - 9)
        raw.put(13, 0)
    }

    /** 1 (min) or 3 (max). */
    fun setFan(fan: Int) {
        raw.set(18, 4, 4, if (fan == 1 || fan == FAN_MAX) fan else FAN_MAX)
        raw.put(13, 0)
    }

    fun setSwingHorizontal(position: Int) =
        raw.set(18, 0, 4, if (position == SWING_H_OFF || position == SWING_H_AUTO) position else SWING_H_AUTO)

    fun finish(): ByteArray {
        raw.put(6, sumBytes(raw, 0, 6))
        raw.put(21, sumBytes(raw, 7, 14))
        return raw.copyOf()
    }

    companion object {
        const val FAN = 0b000
        const val HEAT = 0b001
        const val COOL = 0b010
        const val AUTO = 0b011
        const val DRY = 0b111
        const val MODE_BUTTON = 0b00000100
        const val DRY_FAN_TEMP = 17
        const val FAN_MAX = 3
        const val SWING_H_AUTO = 0x5
        const val SWING_H_OFF = 0x6
        val TIMING = BitTiming(5070, 2140, 370, 1780, 710, 29410)

        fun send(data: ByteArray) = IrFrame(
            38000,
            PulseBuilder()
                .section(TIMING, data, 0, 7)
                .section(TIMING, data, 7, data.size - 7)
                .build(),
        )
    }
}

object Daikin176 : DaikinProtocol {
    override val id = "DAIKIN176"
    override val displayName = "Daikin176"
    override val remotes = "BRC4C151, BRC4C153, FFQ35B8V1B (ceiling cassettes)"
    override val modes = ALL_MODES
    override val fans = listOf(Fan.L1, Fan.L5)
    override val supportsSwingV = false
    override val supportsSwingH = true
    override val nativeTimer = false

    override fun tempRange(mode: Mode) = if (mode == Mode.HEAT) 10..30 else 18..32

    override fun encode(state: AcState, button: Button, now: LocalDateTime?): IrFrame {
        val ac = Daikin176State()
        ac.setMode(
            when (state.mode) {
                Mode.AUTO -> Daikin176State.AUTO
                Mode.COOL -> Daikin176State.COOL
                Mode.DRY -> Daikin176State.DRY
                Mode.HEAT -> Daikin176State.HEAT
                Mode.FAN -> Daikin176State.FAN
            },
        )
        ac.setPower(state.power)
        ac.setTemp(state.tempC)
        ac.setFan(if (state.fan == Fan.L1 || state.fan == Fan.L2) 1 else Daikin176State.FAN_MAX)
        ac.setSwingHorizontal(if (state.swingH) Daikin176State.SWING_H_AUTO else Daikin176State.SWING_H_OFF)
        // The remote flags frames sent by the Mode button.
        if (button == Button.MODE) ac.raw.put(13, Daikin176State.MODE_BUTTON)
        return Daikin176State.send(ac.finish())
    }
}
