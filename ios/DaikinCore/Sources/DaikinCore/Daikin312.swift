import Foundation

/// Port of IRremoteESP8266 `IRDaikin312` (DAIKIN312, 312 bits / 39 bytes).
struct Daikin312State {
    static let length = 39
    static let swingAuto = 0xF
    static let swingOff = 0x0
    static let freq = 36700
    private static let hdrGap = 25100
    static let timing = BitTiming(3518, 1688, 453, 1275, 414, 35512)

    var raw = [UInt8](repeating: 0, count: length)

    init() { reset() }

    mutating func reset() {
        raw = bytesOf(
            0x11, 0xDA, 0x27, 0x00, 0x02, 0x58, 0x64, 0x00, 0x64, 0x00,
            0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x11, 0xDA, 0x27, 0x00, 0x00, 0x08, 0x2C, 0x00, 0x00, 0x00,
            0x00, 0x06, 0x60, 0x00, 0x00, 0xC5, 0x00, 0x08, 0x00
        )
        disableOnTimer()
        disableOffTimer()
        checksum()
    }

    private var mode: Int { raw.get(25, 4, 3) }
    private var tempC: Int { raw.get(26, 0, 7) / 2 }

    mutating func setPower(_ on: Bool) {
        raw.set(25, 0, 1, on ? 1 : 0)
        raw.set(6, 7, 1, on ? 0 : 1) // Power2
    }

    mutating func setMode(_ code: Int) {
        let m = [0b011, 0b100, 0b110, 0b010].contains(code) ? code : 0
        raw.set(25, 4, 3, m)
        if m == 0b011 { setTemp(tempC) }
    }

    mutating func setTemp(_ c: Int) {
        let min = mode == 0b011 ? Daikin2State.minCoolTemp : Daikin280State.minTemp
        raw.set(26, 0, 7, c.clamped(min...Daikin280State.maxTemp) * 2)
    }

    mutating func setFan(_ fan: Int) { raw.set(28, 4, 4, daikinFanCode(fan)) }

    mutating func setSwingVertical(_ position: Int) { raw.set(28, 0, 4, position) }
    mutating func setSwingHorizontal(_ position: Int) { raw.set(29, 0, 4, position) }

    mutating func setCurrentTime(_ mins: Int) { raw.set(5, 0, 12, mins > 24 * 60 ? 0 : mins) }

    mutating func enableOnTimer(_ start: Int) {
        raw.set(36, 5, 1, 0) // SleepTimer
        raw.set(25, 1, 1, 1)
        raw.set(30, 0, 12, start)
    }

    mutating func disableOnTimer() {
        raw.set(30, 0, 12, Daikin280State.unusedTime)
        raw.set(25, 1, 1, 0)
        raw.set(36, 5, 1, 0)
    }

    mutating func enableOffTimer(_ end: Int) { raw.set(25, 2, 1, 1); raw.set(31, 4, 12, end) }
    mutating func disableOffTimer() { raw.set(31, 4, 12, Daikin280State.unusedTime); raw.set(25, 2, 1, 0) }

    mutating func checksum() {
        raw.put(19, sumBytes(raw, 0, 19))
        raw.put(38, sumBytes(raw, 20, 18))
    }

    mutating func finish() -> [UInt8] {
        checksum()
        return raw
    }

    static func send(_ data: [UInt8]) -> IrFrame {
        IrFrame(
            frequencyHz: freq,
            pattern: PulseBuilder()
                .zeroBits(timing, 5, gap: hdrGap)
                .section(timing, data, from: 0, length: 20)
                .section(timing, data, from: 20, length: length - 20)
                .build()
        )
    }
}

public struct Daikin312: DaikinProtocol {
    public let id = "DAIKIN312"
    public let displayName = "Daikin312"
    public let remotes = "ARC466A58, ARC466A67, ARC472A43, FTXM20R5V1B"
    public let modes = allModes
    public let fans = allFans
    public let supportsSwingV = true
    public let supportsSwingH = true
    public let nativeTimer = true

    public func tempRange(_ mode: Mode) -> ClosedRange<Int> { mode == .heat ? 10...30 : 18...32 }

    public func encode(_ state: AcState, button: RemoteKey, now: Date?) -> IrFrame {
        var ac = Daikin312State()
        ac.setPower(state.power)
        ac.setMode(state.mode.daikinCode)
        ac.setTemp(state.tempC)
        ac.setFan(state.fan.daikinCode)
        ac.setSwingVertical(state.swingV ? Daikin312State.swingAuto : Daikin312State.swingOff)
        ac.setSwingHorizontal(state.swingH ? Daikin312State.swingAuto : Daikin312State.swingOff)
        if let now { ac.setCurrentTime(minutesOfDay(now)) }
        if let at = state.onTimerAt { ac.enableOnTimer(minutesOfDay(at)) } else { ac.disableOnTimer() }
        if let at = state.offTimerAt { ac.enableOffTimer(minutesOfDay(at)) } else { ac.disableOffTimer() }
        return Daikin312State.send(ac.finish())
    }
}
