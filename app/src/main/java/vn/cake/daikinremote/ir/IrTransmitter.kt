package vn.cake.daikinremote.ir

import android.content.Context
import android.hardware.ConsumerIrManager
import kotlin.math.abs

class IrTransmitter(context: Context) {
    private val manager = context.getSystemService(Context.CONSUMER_IR_SERVICE) as ConsumerIrManager?

    val hasEmitter: Boolean = manager?.hasIrEmitter() == true

    /** Returns null on success, or an error message. */
    fun send(frame: IrFrame): String? {
        val ir = manager ?: return "No IR service on this device"
        if (!hasEmitter) return "This phone has no IR blaster"
        // A trailing space carries no information, so the pattern ends on a mark.
        val p = frame.pattern
        val pattern = if (p.size % 2 == 0) p.copyOf(p.size - 1) else p
        return try {
            ir.transmit(closestFrequency(ir, frame.frequencyHz), pattern)
            null
        } catch (e: Exception) {
            e.message ?: e.javaClass.simpleName
        }
    }

    private fun closestFrequency(ir: ConsumerIrManager, wanted: Int): Int {
        val ranges = ir.carrierFrequencies ?: return wanted
        if (ranges.isEmpty() || ranges.any { wanted in it.minFrequency..it.maxFrequency }) return wanted
        return ranges.map { wanted.coerceIn(it.minFrequency, it.maxFrequency) }.minBy { abs(it - wanted) }
    }
}
