package vn.cake.daikinremote.ir

/**
 * Builds a ConsumerIrManager pattern (alternating mark/space durations in µs, starting with a
 * mark). Mirrors IRremoteESP8266's `IRsend::sendGeneric` with LSB-first byte order.
 */
class PulseBuilder {
    private val pulses = ArrayList<Int>(1024)

    fun mark(us: Int) = apply { add(us, isMark = true) }

    fun space(us: Int) = apply { add(us, isMark = false) }

    /** Header (optional) + bytes LSB first + footer mark + gap. Zero header values are skipped. */
    fun section(
        timing: BitTiming,
        data: ByteArray,
        from: Int = 0,
        length: Int = data.size - from,
        hdrMark: Int = timing.hdrMark,
        hdrSpace: Int = timing.hdrSpace,
        footerMark: Int = timing.bitMark,
        gap: Int = timing.gap,
    ) = apply {
        mark(hdrMark)
        space(hdrSpace)
        for (i in from until from + length) {
            val b = data[i].toInt() and 0xFF
            for (bit in 0 until 8) bit(timing, (b shr bit) and 1 == 1)
        }
        mark(footerMark)
        space(gap)
    }

    /** `count` zero bits with no header, then footer mark + gap (the Daikin "leader"). */
    fun zeroBits(timing: BitTiming, count: Int, gap: Int) = apply {
        repeat(count) { bit(timing, false) }
        mark(timing.bitMark)
        space(gap)
    }

    private fun bit(t: BitTiming, one: Boolean) {
        mark(t.bitMark)
        space(if (one) t.oneSpace else t.zeroSpace)
    }

    // Merges consecutive marks/spaces so the pattern always alternates.
    private fun add(us: Int, isMark: Boolean) {
        if (us <= 0) return
        if (pulses.isEmpty() && !isMark) return
        val lastIsMark = pulses.size % 2 == 1
        if (pulses.isNotEmpty() && lastIsMark == isMark) {
            pulses[pulses.size - 1] += us
        } else {
            pulses.add(us)
        }
    }

    fun build(): IntArray = pulses.toIntArray()
}

data class BitTiming(
    val hdrMark: Int,
    val hdrSpace: Int,
    val bitMark: Int,
    val oneSpace: Int,
    val zeroSpace: Int,
    val gap: Int,
)

/** A ready-to-send IR frame. */
class IrFrame(val frequencyHz: Int, val pattern: IntArray)
