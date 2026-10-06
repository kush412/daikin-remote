import Foundation

/// Mode/fan codes shared by DAIKIN128 and DAIKIN64.
enum Daikin128Codes {
    static let dry = 0b0001
    static let cool = 0b0010
    static let fan = 0b0100
    static let heat = 0b1000
    static let auto = 0b1010

    static let fanAuto = 0b0001
    static let fanHigh = 0b0010
    static let fanMed = 0b0100
    static let fanLow = 0b1000
    static let fanPowerful = 0b0011
    static let fanQuiet = 0b1001

    static func fanCode(_ f: Fan) -> Int {
        switch f {
        case .auto: fanAuto
        case .quiet: fanQuiet
        case .l1, .l2: fanLow
        case .l3: fanMed
        case .l4, .l5: fanHigh
        }
    }

    static func modeCode(_ m: Mode) -> Int {
        switch m {
        case .auto: auto
        case .cool: cool
        case .dry: dry
        case .heat: heat
        case .fan: fan
        }
    }

    // Leader 2× (9800/9800), then header 4600/2500.
    static let leader = 9800
    static let timing = BitTiming(4600, 2500, 350, 954, 382, 20300)
}

/// Port of IRremoteESP8266 `IRDaikin128` (DAIKIN128, 128 bits / 16 bytes).
struct Daikin128State {
    static let minTemp = 16
    static let maxTemp = 30

    var raw: [UInt8] = {
        var r = [UInt8](repeating: 0, count: 16)
        r.put(0, 0x16); r.put(7, 0x04); r.put(8, 0xA1)
        return r
    }()

    private var mode: Int { raw.get(1, 0, 4) }

    /// The power bit means "toggle power".
    mutating func setPowerToggle(_ toggle: Bool) { raw.set(7, 3, 1, toggle ? 1 : 0) }

    mutating func setMode(_ code: Int) {
        let valid = [Daikin128Codes.auto, Daikin128Codes.cool, Daikin128Codes.heat, Daikin128Codes.fan, Daikin128Codes.dry]
        raw.set(1, 0, 4, valid.contains(code) ? code : Daikin128Codes.auto)
        setFan(raw.get(1, 4, 4)) // Quiet/Powerful depend on mode.
    }

    mutating func setTemp(_ c: Int) { raw.put(6, toBcd(c.clamped(Self.minTemp...Self.maxTemp))) }

    mutating func setFan(_ speed: Int) {
        var s = speed
        switch speed {
        case Daikin128Codes.fanQuiet, Daikin128Codes.fanPowerful:
            if mode == Daikin128Codes.auto { s = Daikin128Codes.fanAuto }
        case Daikin128Codes.fanAuto, Daikin128Codes.fanHigh, Daikin128Codes.fanMed, Daikin128Codes.fanLow:
            break
        default:
            s = Daikin128Codes.fanAuto
        }
        raw.set(1, 4, 4, s)
    }

    mutating func setSwingVertical(_ on: Bool) { raw.set(7, 0, 1, on ? 1 : 0) }

    mutating func setClock(_ mins: Int) {
        let m = mins >= 24 * 60 ? 0 : mins
        raw.put(3, toBcd(m / 60))
        raw.put(2, toBcd(m % 60))
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
        raw.set(7, 4, 4, sumNibbles(raw, 0, 7, raw.u(7) & 0x0F) & 0x0F)
        raw.put(15, sumNibbles(raw, 8, 7))
        return raw
    }

    static func send(_ data: [UInt8]) -> IrFrame {
        let t = Daikin128Codes.timing
        return IrFrame(
            frequencyHz: 38000,
            pattern: PulseBuilder()
                .mark(Daikin128Codes.leader).space(Daikin128Codes.leader)
                .mark(Daikin128Codes.leader).space(Daikin128Codes.leader)
                .section(t, data, from: 0, length: 8)
                .section(t, data, from: 8, length: 8, hdrMark: 0, hdrSpace: 0, footerMark: t.hdrMark)
                .build()
        )
    }
}

public struct Daikin128: DaikinProtocol {
    public let id = "DAIKIN128"
    public let displayName = "Daikin128"
    public let remotes = "BRC52B63, 17 Series FTXB**AXVJU"
    public let modes = allModes
    public let fans: [Fan] = [.auto, .quiet, .l1, .l3, .l5]
    public let supportsSwingV = true
    public let supportsSwingH = false
    public let nativeTimer = true
    public let powerIsToggle = true

    public func tempRange(_ mode: Mode) -> ClosedRange<Int> { Daikin128State.minTemp...Daikin128State.maxTemp }

    public func encode(_ state: AcState, button: RemoteKey, now: Date?) -> IrFrame {
        var ac = Daikin128State()
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
        return Daikin128State.send(ac.finish())
    }
}
