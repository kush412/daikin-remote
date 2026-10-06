package vn.cake.daikinremote.protocol

// Little-endian bitfield helpers matching the GCC bitfield layout used by IRremoteESP8266.

/** Set a field of [nbits] starting at bit [bit] of byte [byte] (may span bytes). */
internal fun ByteArray.set(byte: Int, bit: Int, nbits: Int, value: Int) {
    val start = byte * 8 + bit
    for (i in 0 until nbits) {
        val pos = start + i
        val idx = pos / 8
        val mask = 1 shl (pos % 8)
        val v = this[idx].toInt() and 0xFF
        this[idx] = (if ((value shr i) and 1 == 1) v or mask else v and mask.inv()).toByte()
    }
}

internal fun ByteArray.get(byte: Int, bit: Int, nbits: Int): Int {
    val start = byte * 8 + bit
    var out = 0
    for (i in 0 until nbits) {
        val pos = start + i
        if ((this[pos / 8].toInt() shr (pos % 8)) and 1 == 1) out = out or (1 shl i)
    }
    return out
}

internal fun ByteArray.u(i: Int): Int = this[i].toInt() and 0xFF

internal fun ByteArray.put(i: Int, v: Int) {
    this[i] = v.toByte()
}

internal fun sumBytes(data: ByteArray, from: Int, length: Int, init: Int = 0): Int {
    var s = init
    for (i in from until from + length) s += data.u(i)
    return s and 0xFF
}

internal fun sumNibbles(data: ByteArray, from: Int, length: Int, init: Int = 0): Int {
    var s = init
    for (i in from until from + length) s += (data.u(i) shr 4) + (data.u(i) and 0xF)
    return s and 0xFF
}

internal fun toBcd(v: Int): Int = ((v / 10) shl 4) + (v % 10)

fun bytesOf(vararg v: Int) = ByteArray(v.size) { v[it].toByte() }

fun ByteArray.toHex(): String = joinToString(" ") { "%02X".format(it.toInt() and 0xFF) }
