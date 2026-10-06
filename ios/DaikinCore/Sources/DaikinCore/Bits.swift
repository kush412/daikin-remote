import Foundation

// Little-endian bitfield helpers matching the GCC bitfield layout used by IRremoteESP8266.

extension Array where Element == UInt8 {
    /// Set a field of `nbits` starting at bit `bit` of byte `byte` (may span bytes).
    mutating func set(_ byte: Int, _ bit: Int, _ nbits: Int, _ value: Int) {
        let start = byte * 8 + bit
        for i in 0..<nbits {
            let pos = start + i
            let mask = UInt8(1 << (pos % 8))
            if (value >> i) & 1 == 1 {
                self[pos / 8] |= mask
            } else {
                self[pos / 8] &= ~mask
            }
        }
    }

    func get(_ byte: Int, _ bit: Int, _ nbits: Int) -> Int {
        let start = byte * 8 + bit
        var out = 0
        for i in 0..<nbits {
            let pos = start + i
            if (Int(self[pos / 8]) >> (pos % 8)) & 1 == 1 { out |= 1 << i }
        }
        return out
    }

    func u(_ i: Int) -> Int { Int(self[i]) }

    mutating func put(_ i: Int, _ v: Int) {
        self[i] = UInt8(truncatingIfNeeded: v)
    }

    public var hex: String { map { String(format: "%02X", $0) }.joined(separator: " ") }
}

func sumBytes(_ data: [UInt8], _ from: Int, _ length: Int, _ initial: Int = 0) -> Int {
    var s = initial
    for i in from..<(from + length) { s += data.u(i) }
    return s & 0xFF
}

func sumNibbles(_ data: [UInt8], _ from: Int, _ length: Int, _ initial: Int = 0) -> Int {
    var s = initial
    for i in from..<(from + length) { s += (data.u(i) >> 4) + (data.u(i) & 0xF) }
    return s & 0xFF
}

func toBcd(_ v: Int) -> Int { ((v / 10) << 4) + (v % 10) }

public func bytesOf(_ v: Int...) -> [UInt8] { v.map { UInt8(truncatingIfNeeded: $0) } }

extension Int {
    func clamped(_ range: ClosedRange<Int>) -> Int { Swift.min(Swift.max(self, range.lowerBound), range.upperBound) }
}
