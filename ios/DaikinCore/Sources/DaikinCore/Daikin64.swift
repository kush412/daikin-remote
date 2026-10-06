import Foundation

/// Port of IRremoteESP8266 `IRDaikin64` (DAIKIN64, 64 bits). Held as 8 little-endian bytes,
/// which is exactly the LSB-first order the 64-bit value is transmitted in.
struct Daikin64State {
    // kDaikin64KnownGoodState = 0x7C16161607204216
    var raw = bytesOf(0x16, 0x42, 0x20, 0x07, 0x16, 0x16, 0x16, 0x7C)

    mutating func setPowerToggle(_ toggle: Bool) { raw.set(7, 3, 1, toggle ? 1 : 0) }

    mutating func setMode(_ code: Int) {
        let valid = [Daikin128Codes.fan, Daikin128Codes.dry, Daikin128Codes.cool, Daikin128Codes.heat]
        raw.set(1, 0, 4, valid.contains(code) ? code : Daikin128Codes.cool)
    }

    mutating func setTemp(_ c: Int) {
        raw.put(6, toBcd(c.clamped(Daikin128State.minTemp...Daikin128State.maxTemp)))
    }

    mutating func setFan(_ speed: Int) { raw.set(1, 4, 4, speed) }

    mutating func setSwingVertical(_ on: Bool) { raw.set(7, 0, 1, on ? 1 : 0) }

    mutating func setClock(_ mins: Int) {
        let m = mins >= 24 * 60 ? 0 : mins
        raw.put(2, toBcd(m % 60))
        raw.put(3, toBcd(m / 60))
    }

    mutating func setOnTimerEnabled(_ on: Bool) { raw.set(4, 7, 1, on ? 1 : 0) }
    mutating func setOnTimer(_ mins: Int) { setTime(4, mins) }
    mutating func setOffTimerEnabled(_ on: Bool) { raw.set(5, 7, 1, on ? 1 : 0) }
    mutating func setOffTimer(_ mins: Int) { setTime(5, mins) }

    private mutating func setTime(_ byte: Int, _ minsSinceMidnight: Int) {
        let mins = minsSinceMidnight >= 24 * 60 ? 0 : minsSinceMidnight
        raw.set(byte, 6, 1, mins % 60 >= 30 ? 1 : 0)
        raw.set(byte, 0, 6, toBcd(mins / 60))
    }

    mutating func finish() -> [UInt8] {
        // Sum of the 15 nibbles below the checksum nibble.
        let sum = sumNibbles(raw, 0, 7, raw.u(7) & 0x0F) & 0x0F
        raw.set(7, 4, 4, sum)
        return raw
    }

    var uint64: UInt64 {
        raw.enumerated().reduce(UInt64(0)) { acc, e in acc | (UInt64(e.element) << (8 * UInt64(e.offset))) }
    }

    static func send(_ data: [UInt8]) -> IrFrame {
        let t = Daikin128Codes.timing
        return IrFrame(
            frequencyHz: 38000,
            pattern: PulseBuilder()
                .mark(Daikin128Codes.leader).space(Daikin128Codes.leader)
                .mark(Daikin128Codes.leader).space(Daikin128Codes.leader)
                .section(t, data)
                .mark(t.hdrMark).space(100_000)
                .build()
        )
    }
}

public struct Daikin64: DaikinProtocol {
    public let id = "DAIKIN64"
    public let displayName = "Daikin64"
    public let remotes = "DGS01, BRC4C158, FFN-C/FCN-F, FTWX35AXV1"
    public let modes: [Mode] = [.cool, .dry, .heat, .fan]
    public let fans: [Fan] = [.auto, .quiet, .l1, .l3, .l5]
    public let supportsSwingV = true
    public let supportsSwingH = false
    public let nativeTimer = true
    public let powerIsToggle = true

    public func tempRange(_ mode: Mode) -> ClosedRange<Int> { Daikin128State.minTemp...Daikin128State.maxTemp }

    public func encode(_ state: AcState, button: RemoteKey, now: Date?) -> IrFrame {
        var ac = Daikin64State()
        ac.setPowerToggle(button == .power)
        ac.setMode(Daikin128Codes.modeCode(state.mode))
        ac.setTemp(state.tempC)
        ac.setFan(Daikin128Codes.fanCode(state.fan))
        ac.setSwingVertical(state.swingV)
        if let now { ac.setClock(minutesOfDay(now)) }
        ac.setOnTimerEnabled(state.onTimerAt != nil)
        if let at = state.onTimerAt { ac.setOnTimer(minutesOfDay(at)) }
        ac.setOffTimerEnabled(state.offTimerAt != nil)
        if let at = state.offTimerAt { ac.setOffTimer(minutesOfDay(at)) }
        return Daikin64State.send(ac.finish())
    }
}
