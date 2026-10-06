import Foundation

/// Port of IRremoteESP8266 `IRDaikin2` (DAIKIN2, 312 bits / 39 bytes).
struct Daikin2State {
    static let length = 39
    static let minCoolTemp = 18
    static let swingVAuto = 0xF
    static let swingVOff = 0xE
    static let swingHAuto = 0xBE
    static let swingHOff = 0xBF
    static let freq = 36700
    private static let leaderMark = 10024
    private static let leaderSpace = 25180
    static let timing = BitTiming(3500, 1728, 460, 1270, 420, leaderMark + leaderSpace)

    var raw = [UInt8](repeating: 0, count: length)

    init() { reset() }

    mutating func reset() {
        raw = bytesOf(
            0x11, 0xDA, 0x27, 0x00, 0x01, 0x00, 0xC0, 0x70, 0x08, 0x0C,
            0x80, 0x04, 0xB0, 0x16, 0x24, 0x00, 0x00, 0xBE, 0xD0, 0x00,
            0x11, 0xDA, 0x27, 0x00, 0x00, 0x08, 0x00, 0x00, 0xA0, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0xC1, 0x80, 0x60, 0x00
        )
        disableOnTimer()
        disableOffTimer()
        checksum()
    }

    private var mode: Int { raw.get(25, 4, 3) }
    private var temp: Int { raw.get(26, 1, 6) }

    mutating func setPower(_ on: Bool) {
        raw.set(25, 0, 1, on ? 1 : 0)
        raw.set(6, 7, 1, on ? 0 : 1) // Power2
    }

    mutating func setMode(_ code: Int) {
        let m = [0b011, 0b100, 0b110, 0b010].contains(code) ? code : 0
        raw.set(25, 4, 3, m)
        if m == 0b011 { setTemp(temp) } // Cool has a different minimum temperature.
    }

    mutating func setTemp(_ c: Int) {
        let min = mode == 0b011 ? Self.minCoolTemp : Daikin280State.minTemp
        raw.set(26, 1, 6, c.clamped(min...Daikin280State.maxTemp))
    }

    mutating func setFan(_ fan: Int) { raw.set(28, 4, 4, daikinFanCode(fan)) }

    mutating func setSwingVertical(_ position: Int) { raw.set(18, 0, 4, position) }
    mutating func setSwingHorizontal(_ position: Int) { raw.put(17, position) }

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

    mutating func setBeep(_ beep: Int) { raw.set(7, 6, 2, beep) }
    mutating func setLight(_ light: Int) { raw.set(7, 4, 2, light) }
    mutating func setMold(_ on: Bool) { raw.set(8, 3, 1, on ? 1 : 0) }
    mutating func setClean(_ on: Bool) { raw.set(8, 5, 1, on ? 1 : 0) }

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
                .mark(leaderMark).space(leaderSpace)
                .section(timing, data, from: 0, length: 20)
                .section(timing, data, from: 20, length: length - 20)
                .build()
        )
    }
}

public struct Daikin2: DaikinProtocol {
    public let id = "DAIKIN2"
    public let displayName = "Daikin2 (312-bit)"
    public let remotes = "ARC477A1, FTXZ**NV1B"
    public let modes = allModes
    public let fans = allFans
    public let supportsSwingV = true
    public let supportsSwingH = true
    public let nativeTimer = true

    public func tempRange(_ mode: Mode) -> ClosedRange<Int> { mode == .heat ? 10...30 : 18...32 }

    public func encode(_ state: AcState, button: RemoteKey, now: Date?) -> IrFrame {
        var ac = Daikin2State()
        ac.setPower(state.power)
        ac.setMode(state.mode.daikinCode)
        ac.setTemp(state.tempC)
        ac.setFan(state.fan.daikinCode)
        ac.setSwingVertical(state.swingV ? Daikin2State.swingVAuto : Daikin2State.swingVOff)
        ac.setSwingHorizontal(state.swingH ? Daikin2State.swingHAuto : Daikin2State.swingHOff)
        if let now { ac.setCurrentTime(minutesOfDay(now)) }
        if let at = state.onTimerAt { ac.enableOnTimer(minutesOfDay(at)) } else { ac.disableOnTimer() }
        if let at = state.offTimerAt { ac.enableOffTimer(minutesOfDay(at)) } else { ac.disableOffTimer() }
        return Daikin2State.send(ac.finish())
    }
}
