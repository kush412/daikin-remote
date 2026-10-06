import Foundation

/// Port of IRremoteESP8266 `IRDaikin160` (DAIKIN160, 160 bits / 20 bytes).
struct Daikin160State {
    static let swingLowest = 0x1
    static let swingAuto = 0xF
    static let timing = BitTiming(5000, 2145, 342, 1786, 700, 29650)

    var raw = bytesOf(
        0x11, 0xDA, 0x27, 0xF0, 0x0D, 0x00, 0x00,
        0x11, 0xDA, 0x27, 0x00, 0xD3, 0x30, 0x11, 0x00, 0x00, 0x1E, 0x0A, 0x08, 0x00
    )

    mutating func setPower(_ on: Bool) { raw.set(12, 0, 1, on ? 1 : 0) }
    mutating func setMode(_ code: Int) { raw.set(12, 4, 3, code) }
    mutating func setTemp(_ c: Int) {
        raw.set(16, 1, 6, c.clamped(Daikin280State.minTemp...Daikin280State.maxTemp) - 10)
    }

    mutating func setFan(_ fan: Int) { raw.set(17, 0, 4, daikinFanCode(fan)) }

    /// 1 (lowest) … 5 (highest), or 0xF for auto swing.
    mutating func setSwingVertical(_ position: Int) {
        raw.set(13, 4, 4, (1...5).contains(position) ? position : Self.swingAuto)
    }

    mutating func finish() -> [UInt8] {
        raw.put(6, sumBytes(raw, 0, 6))
        raw.put(19, sumBytes(raw, 7, 12))
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

public struct Daikin160: DaikinProtocol {
    public let id = "DAIKIN160"
    public let displayName = "Daikin160"
    public let remotes = "ARC423A5, FTE12HV2S"
    public let modes = allModes
    public let fans = allFans
    public let supportsSwingV = true
    public let supportsSwingH = false
    public let nativeTimer = false

    public func tempRange(_ mode: Mode) -> ClosedRange<Int> { mode == .heat ? 10...30 : 18...32 }

    public func encode(_ state: AcState, button: RemoteKey, now: Date?) -> IrFrame {
        var ac = Daikin160State()
        ac.setPower(state.power)
        ac.setMode(state.mode.daikinCode)
        ac.setTemp(state.tempC)
        ac.setFan(state.fan.daikinCode)
        // No "off" position exists; swing off parks the vane at its reset (lowest) position.
        ac.setSwingVertical(state.swingV ? Daikin160State.swingAuto : Daikin160State.swingLowest)
        return Daikin160State.send(ac.finish())
    }
}
