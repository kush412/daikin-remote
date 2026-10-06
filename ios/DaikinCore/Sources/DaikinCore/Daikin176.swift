import Foundation

/// Port of IRremoteESP8266 `IRDaikin176` (DAIKIN176, 176 bits / 22 bytes).
struct Daikin176State {
    static let fan = 0b000
    static let heat = 0b001
    static let cool = 0b010
    static let auto = 0b011
    static let dry = 0b111
    static let modeButton = 0b00000100
    static let dryFanTemp = 17
    static let fanMax = 3
    static let swingHAuto = 0x5
    static let swingHOff = 0x6
    static let timing = BitTiming(5070, 2140, 370, 1780, 710, 29410)

    var raw = bytesOf(
        0x11, 0xDA, 0x17, 0x18, 0x04, 0x00, 0x00,
        0x11, 0xDA, 0x17, 0x18, 0x00, 0x73, 0x00, 0x20, 0x00, 0x00, 0x00, 0x16, 0x00, 0x20, 0x00
    )
    private var savedTemp: Int

    init() { savedTemp = raw.get(17, 1, 6) + 9 }

    private var mode: Int { raw.get(14, 4, 3) }

    mutating func setPower(_ on: Bool) {
        raw.put(13, 0) // ModeButton
        raw.set(14, 0, 1, on ? 1 : 0)
    }

    mutating func setMode(_ code: Int) {
        var m = code
        let alt: Int
        switch code {
        case Self.dry: alt = 2
        case Self.fan: alt = 6
        case Self.auto, Self.cool, Self.heat: alt = 7
        default:
            m = Self.cool
            alt = 7
        }
        raw.set(14, 4, 3, m)
        raw.set(12, 4, 3, alt)
        setTemp(savedTemp)
        raw.put(13, Self.modeButton) // Must follow setTemp(), which clears it.
    }

    mutating func setTemp(_ c: Int) {
        var degrees = c.clamped(Daikin280State.minTemp...Daikin280State.maxTemp)
        savedTemp = degrees
        if mode == Self.dry || mode == Self.fan { degrees = Self.dryFanTemp }
        raw.set(17, 1, 6, degrees - 9)
        raw.put(13, 0)
    }

    /// 1 (min) or 3 (max).
    mutating func setFan(_ fan: Int) {
        raw.set(18, 4, 4, fan == 1 || fan == Self.fanMax ? fan : Self.fanMax)
        raw.put(13, 0)
    }

    mutating func setSwingHorizontal(_ position: Int) {
        raw.set(18, 0, 4, position == Self.swingHOff || position == Self.swingHAuto ? position : Self.swingHAuto)
    }

    mutating func finish() -> [UInt8] {
        raw.put(6, sumBytes(raw, 0, 6))
        raw.put(21, sumBytes(raw, 7, 14))
        return raw
    }

    static func send(_ data: [UInt8]) -> IrFrame {
        IrFrame(
            frequencyHz: 38000,
            pattern: PulseBuilder()
                .section(timing, data, from: 0, length: 7)
                .section(timing, data, from: 7, length: data.count - 7)
                .build()
        )
    }
}

public struct Daikin176: DaikinProtocol {
    public let id = "DAIKIN176"
    public let displayName = "Daikin176"
    public let remotes = "BRC4C151, BRC4C153, FFQ35B8V1B (ceiling cassettes)"
    public let modes = allModes
    public let fans: [Fan] = [.l1, .l5]
    public let supportsSwingV = false
    public let supportsSwingH = true
    public let nativeTimer = false

    public func tempRange(_ mode: Mode) -> ClosedRange<Int> { mode == .heat ? 10...30 : 18...32 }

    public func encode(_ state: AcState, button: RemoteKey, now: Date?) -> IrFrame {
        var ac = Daikin176State()
        switch state.mode {
        case .auto: ac.setMode(Daikin176State.auto)
        case .cool: ac.setMode(Daikin176State.cool)
        case .dry: ac.setMode(Daikin176State.dry)
        case .heat: ac.setMode(Daikin176State.heat)
        case .fan: ac.setMode(Daikin176State.fan)
        }
        ac.setPower(state.power)
        ac.setTemp(state.tempC)
        ac.setFan(state.fan == .l1 || state.fan == .l2 ? 1 : Daikin176State.fanMax)
        ac.setSwingHorizontal(state.swingH ? Daikin176State.swingHAuto : Daikin176State.swingHOff)
        // The remote flags frames sent by the Mode button.
        if button == .mode { ac.raw.put(13, Daikin176State.modeButton) }
        return Daikin176State.send(ac.finish())
    }
}
