import Foundation

/// Port of IRremoteESP8266 `IRDaikin152` (DAIKIN152, 152 bits / 19 bytes).
struct Daikin152State {
    static let length = 19
    static let fanTemp = 0x60
    static let maxTimerMinutes = 12 * 60
    static let timing = BitTiming(3492, 1718, 433, 1529, 433, 25182)

    var raw = [UInt8](repeating: 0, count: length)

    init() {
        raw.put(0, 0x11); raw.put(1, 0xDA); raw.put(2, 0x27); raw.put(15, 0xC5)
    }

    private var mode: Int { raw.get(5, 4, 3) }

    mutating func setPower(_ on: Bool) { raw.set(5, 0, 1, on ? 1 : 0) }

    mutating func setMode(_ code: Int) {
        switch code {
        case 0b110: setTemp(Self.fanTemp) // Fan mode uses a special temperature.
        case 0b010: setTemp(Daikin2State.minCoolTemp) // Dry is fixed at 18°C.
        case 0b000, 0b011, 0b100: break
        default:
            raw.set(5, 4, 3, 0)
            return
        }
        raw.set(5, 4, 3, code)
    }

    mutating func setTemp(_ c: Int) {
        let min = mode == 0b100 ? Daikin280State.minTemp : Daikin2State.minCoolTemp
        let degrees = c == Self.fanTemp ? c : c.clamped(min...Daikin280State.maxTemp)
        raw.set(6, 1, 7, degrees)
    }

    mutating func setFan(_ fan: Int) { raw.set(8, 4, 4, daikinFanCode(fan)) }

    mutating func setSwingV(_ on: Bool) { raw.set(8, 0, 4, on ? 0xF : 0) }

    // Timers: not in IRremoteESP8266. The frame matches section 3 of DAIKIN280 (and section 2 of
    // DAIKIN2), whose timer fields sit at the same offsets; a real ARC480A5 "night sleep" capture
    // (issue #873) carries 0x3C (60) there. With no clock in this protocol, the value is the
    // number of minutes from now. Unused timers are sent as 0, as the real remote does.
    // Confirmed working on the real unit.
    mutating func enableOnTimer(_ minutesFromNow: Int) {
        raw.set(5, 1, 1, 1)
        raw.set(10, 0, 12, minutesFromNow.clamped(1...Self.maxTimerMinutes))
    }

    mutating func enableOffTimer(_ minutesFromNow: Int) {
        raw.set(5, 2, 1, 1)
        raw.set(11, 4, 12, minutesFromNow.clamped(1...Self.maxTimerMinutes))
    }

    mutating func finish() -> [UInt8] {
        raw.put(Self.length - 1, sumBytes(raw, 0, Self.length - 1))
        return raw
    }

    static func send(_ data: [UInt8]) -> IrFrame {
        IrFrame(
            frequencyHz: 38000,
            pattern: PulseBuilder()
                .zeroBits(timing, 5, gap: timing.gap)
                .section(timing, data)
                .build()
        )
    }
}

public struct Daikin152: DaikinProtocol {
    public let id = "DAIKIN152"
    public let displayName = "Daikin152"
    public let remotes = "ARC480A5, ARC480A93 (timer support is reverse-engineered)"
    public let modes = allModes
    public let fans = allFans
    public let supportsSwingV = true
    public let supportsSwingH = false
    public let nativeTimer = true

    public func tempRange(_ mode: Mode) -> ClosedRange<Int> { mode == .heat ? 10...30 : 18...32 }

    public func encode(_ state: AcState, button: RemoteKey, now: Date?) -> IrFrame {
        var ac = Daikin152State()
        ac.setPower(state.power)
        // Temp before mode, so Dry/Fan can override it with their fixed values.
        ac.setTemp(state.tempC)
        ac.setMode(state.mode.daikinCode)
        if state.mode == .auto || state.mode == .cool || state.mode == .heat { ac.setTemp(state.tempC) }
        ac.setFan(state.fan.daikinCode)
        ac.setSwingV(state.swingV)
        // Relative timers: re-sent with the remaining minutes on every press, like the remote.
        let reference = now ?? Date()
        if let at = state.onTimerAt { ac.enableOnTimer(minutesUntil(at, reference)) }
        if let at = state.offTimerAt { ac.enableOffTimer(minutesUntil(at, reference)) }
        return Daikin152State.send(ac.finish())
    }
}
