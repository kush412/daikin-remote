/// A ready-to-send IR frame: carrier frequency and alternating mark/space durations in µs,
/// starting with a mark.
public struct IrFrame: Equatable, Sendable {
    public let frequencyHz: Int
    public let pattern: [Int]
}

public struct BitTiming: Sendable {
    let hdrMark: Int
    let hdrSpace: Int
    let bitMark: Int
    let oneSpace: Int
    let zeroSpace: Int
    let gap: Int

    init(_ hdrMark: Int, _ hdrSpace: Int, _ bitMark: Int, _ oneSpace: Int, _ zeroSpace: Int, _ gap: Int) {
        self.hdrMark = hdrMark
        self.hdrSpace = hdrSpace
        self.bitMark = bitMark
        self.oneSpace = oneSpace
        self.zeroSpace = zeroSpace
        self.gap = gap
    }
}

/// Builds a mark/space pattern. Mirrors IRremoteESP8266's `IRsend::sendGeneric` with LSB-first
/// byte order.
final class PulseBuilder {
    private var pulses: [Int] = []

    init() { pulses.reserveCapacity(1024) }

    @discardableResult func mark(_ us: Int) -> Self { add(us, isMark: true); return self }

    @discardableResult func space(_ us: Int) -> Self { add(us, isMark: false); return self }

    /// Header (optional) + bytes LSB first + footer mark + gap. Zero header values are skipped.
    @discardableResult func section(
        _ timing: BitTiming,
        _ data: [UInt8],
        from: Int = 0,
        length: Int? = nil,
        hdrMark: Int? = nil,
        hdrSpace: Int? = nil,
        footerMark: Int? = nil,
        gap: Int? = nil
    ) -> Self {
        mark(hdrMark ?? timing.hdrMark)
        space(hdrSpace ?? timing.hdrSpace)
        for i in from..<(from + (length ?? data.count - from)) {
            let b = Int(data[i])
            for bit in 0..<8 { self.bit(timing, (b >> bit) & 1 == 1) }
        }
        mark(footerMark ?? timing.bitMark)
        space(gap ?? timing.gap)
        return self
    }

    /// `count` zero bits with no header, then footer mark + gap (the Daikin "leader").
    @discardableResult func zeroBits(_ timing: BitTiming, _ count: Int, gap: Int) -> Self {
        for _ in 0..<count { bit(timing, false) }
        mark(timing.bitMark)
        space(gap)
        return self
    }

    private func bit(_ t: BitTiming, _ one: Bool) {
        mark(t.bitMark)
        space(one ? t.oneSpace : t.zeroSpace)
    }

    // Merges consecutive marks/spaces so the pattern always alternates.
    private func add(_ us: Int, isMark: Bool) {
        if us <= 0 { return }
        if pulses.isEmpty && !isMark { return }
        let lastIsMark = pulses.count % 2 == 1
        if !pulses.isEmpty && lastIsMark == isMark {
            pulses[pulses.count - 1] += us
        } else {
            pulses.append(us)
        }
    }

    func build() -> [Int] { pulses }
}
