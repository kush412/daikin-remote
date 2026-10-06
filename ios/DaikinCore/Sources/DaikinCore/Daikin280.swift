import Foundation

/// Port of IRremoteESP8266 `IRDaikinESP` (DAIKIN, 280 bits / 35 bytes).
struct Daikin280State {
    static let length = 35
    static let minTemp = 10
    static let maxTemp = 32
    static let unusedTime = 0x600
    static let freq = 38000
    static let timing = BitTiming(3650, 1623, 428, 1280, 428, 428 + 29000)

    var raw = [UInt8](repeating: 0, count: length)

    init() { reset() }

    mutating func reset() {
        raw = [UInt8](repeating: 0, count: Self.length)
        raw.put(0, 0x11); raw.put(1, 0xDA); raw.put(2, 0x27); raw.put(4, 0xC5)
        raw.put(8, 0x11); raw.put(9, 0xDA); raw.put(10, 0x27); raw.put(12, 0x42)
        raw.put(16, 0x11); raw.put(17, 0xDA); raw.put(18, 0x27)
        raw.put(21, 0x49); raw.put(22, 0x1E); raw.put(24, 0xB0)
        raw.put(27, 0x06); raw.put(28, 0x60); raw.put(31, 0xC0)
        checksum()
    }

    mutating func setPower(_ on: Bool) { raw.set(21, 0, 1, on ? 1 : 0) }

    /// One of the 3-bit Daikin mode codes.
    mutating func setMode(_ code: Int) { raw.set(21, 4, 3, code) }

    mutating func setTemp(_ c: Int) { raw.put(22, c.clamped(Self.minTemp...Self.maxTemp) * 2) }

    /// 1–5, or 0xA (auto) / 0xB (quiet).
    mutating func setFan(_ fan: Int) { raw.set(24, 4, 4, daikinFanCode(fan)) }

    mutating func setSwingVertical(_ on: Bool) { raw.set(24, 0, 4, on ? 0xF : 0) }
    mutating func setSwingHorizontal(_ on: Bool) { raw.set(25, 0, 4, on ? 0xF : 0) }

    mutating func setCurrentTime(_ minsSinceMidnight: Int) {
        raw.set(13, 0, 11, minsSinceMidnight > 24 * 60 ? 0 : minsSinceMidnight)
    }

    mutating func setCurrentDay(_ day: Int) { raw.set(14, 3, 3, day) }

    mutating func enableOnTimer(_ start: Int) { raw.set(21, 1, 1, 1); raw.set(26, 0, 12, start) }
    mutating func disableOnTimer() { raw.set(21, 1, 1, 0); raw.set(26, 0, 12, Self.unusedTime) }
    mutating func enableOffTimer(_ end: Int) { raw.set(21, 2, 1, 1); raw.set(27, 4, 12, end) }
    mutating func disableOffTimer() { raw.set(21, 2, 1, 0); raw.set(27, 4, 12, Self.unusedTime) }

    mutating func checksum() {
        raw.put(7, sumBytes(raw, 0, 7))
        raw.put(15, sumBytes(raw, 8, 7))
        raw.put(34, sumBytes(raw, 16, Self.length - 16 - 1))
    }

    mutating func finish() -> [UInt8] {
        checksum()
        return raw
    }

    static func send(_ data: [UInt8]) -> IrFrame {
        IrFrame(
            frequencyHz: freq,
            pattern: PulseBuilder()
                .zeroBits(timing, 5, gap: timing.gap)
                .section(timing, data, from: 0, length: 8)
                .section(timing, data, from: 8, length: 8)
                .section(timing, data, from: 16, length: length - 16)
                .build()
        )
    }
}

public struct Daikin280: DaikinProtocol {
    public let id = "DAIKIN"
    public let displayName = "Daikin (280-bit)"
    public let remotes = "ARC433**, ARC470A1, ARC466A12/A33, ARC443A5 – most wall splits"
    public let modes = allModes
    public let fans = allFans
    public let supportsSwingV = true
    public let supportsSwingH = true
    public let nativeTimer = true

    public func tempRange(_ mode: Mode) -> ClosedRange<Int> { mode == .heat ? 10...30 : 18...32 }

    public func encode(_ state: AcState, button: RemoteKey, now: Date?) -> IrFrame {
        var ac = Daikin280State()
        ac.setPower(state.power)
        ac.setMode(state.mode.daikinCode)
        switch state.mode {
        // Real ARC remotes send 0xC0 in Dry and 25°C in Fan (see ir_Daikin.h).
        case .dry: ac.raw.put(22, 0xC0)
        case .fan: ac.setTemp(25)
        default: ac.setTemp(state.tempC)
        }
        ac.setFan(state.fan.daikinCode)
        ac.setSwingVertical(state.swingV)
        ac.setSwingHorizontal(state.swingH)
        if let now {
            ac.setCurrentTime(minutesOfDay(now))
            ac.setCurrentDay(daikinDay(now))
        }
        if let at = state.onTimerAt { ac.enableOnTimer(minutesOfDay(at)) } else { ac.disableOnTimer() }
        if let at = state.offTimerAt { ac.enableOffTimer(minutesOfDay(at)) } else { ac.disableOffTimer() }
        return Daikin280State.send(ac.finish())
    }
}
