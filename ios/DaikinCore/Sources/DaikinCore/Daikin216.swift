import Foundation

/// Port of IRremoteESP8266 `IRDaikin216` (DAIKIN216, 216 bits / 27 bytes).
struct Daikin216State {
    static let length = 27
    static let timing = BitTiming(3440, 1750, 420, 1300, 450, 29650)

    var raw = [UInt8](repeating: 0, count: length)

    init() {
        raw.put(0, 0x11); raw.put(1, 0xDA); raw.put(2, 0x27); raw.put(3, 0xF0)
        raw.put(8, 0x11); raw.put(9, 0xDA); raw.put(10, 0x27); raw.put(23, 0xC0)
    }

    mutating func setPower(_ on: Bool) { raw.set(13, 0, 1, on ? 1 : 0) }
    mutating func setMode(_ code: Int) { raw.set(13, 4, 3, code) }
    mutating func setTemp(_ c: Int) { raw.set(14, 1, 6, c.clamped(Daikin280State.minTemp...Daikin280State.maxTemp)) }
    mutating func setFan(_ fan: Int) { raw.set(16, 4, 4, daikinFanCode(fan)) }
    mutating func setSwingVertical(_ on: Bool) { raw.set(16, 0, 4, on ? 0xF : 0) }
    mutating func setSwingHorizontal(_ on: Bool) { raw.set(17, 0, 4, on ? 0xF : 0) }

    mutating func finish() -> [UInt8] {
        raw.put(7, sumBytes(raw, 0, 7))
        raw.put(26, sumBytes(raw, 8, Self.length - 8 - 1))
        return raw
    }

    static func send(_ data: [UInt8]) -> IrFrame {
        IrFrame(
            frequencyHz: 38000,
            pattern: PulseBuilder()
                .section(timing, data, from: 0, length: 8)
                .section(timing, data, from: 8, length: length - 8)
                .build()
        )
    }
}

public struct Daikin216: DaikinProtocol {
    public let id = "DAIKIN216"
    public let displayName = "Daikin216"
    public let remotes = "ARC433B69, ARC484A4, FTQ60TV16U2"
    public let modes = allModes
    public let fans = allFans
    public let supportsSwingV = true
    public let supportsSwingH = true
    public let nativeTimer = false

    public func tempRange(_ mode: Mode) -> ClosedRange<Int> { mode == .heat ? 10...30 : 18...32 }

    public func encode(_ state: AcState, button: RemoteKey, now: Date?) -> IrFrame {
        var ac = Daikin216State()
        ac.setPower(state.power)
        ac.setMode(state.mode.daikinCode)
        ac.setTemp(state.tempC)
        ac.setFan(state.fan.daikinCode)
        ac.setSwingVertical(state.swingV)
        ac.setSwingHorizontal(state.swingH)
        return Daikin216State.send(ac.finish())
    }
}
