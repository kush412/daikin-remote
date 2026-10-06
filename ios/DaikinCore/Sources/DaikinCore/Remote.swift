import Foundation

/// Everything the app persists: the remote state plus settings.
public struct Stored: Codable, Equatable, Sendable {
    public var state = AcState()
    public var protocolId: String?
    /// Run timers on the bridge instead of in the AC (forced for protocols without IR timers).
    public var bridgeTimer = false
    /// Host name or IP of the IR bridge.
    public var bridgeHost = "daikin-ir.local"

    public init() {}

    public var protocolValue: any DaikinProtocol { Protocols.byId(protocolId) }

    /// Timers that are run by the bridge rather than encoded into the IR frame. Toggle-power
    /// protocols always use the AC's own timer: the bridge can't know which way a toggle goes.
    public var usesBridgeTimer: Bool {
        let p = protocolValue
        return !p.nativeTimer || (bridgeTimer && !p.powerIsToggle)
    }

    // Older saves may lack newer keys; fall back to defaults instead of failing.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        state = try c.decodeIfPresent(AcState.self, forKey: .state) ?? AcState()
        protocolId = try c.decodeIfPresent(String.self, forKey: .protocolId)
        bridgeTimer = try c.decodeIfPresent(Bool.self, forKey: .bridgeTimer) ?? false
        bridgeHost = try c.decodeIfPresent(String.self, forKey: .bridgeHost) ?? "daikin-ir.local"
    }
}

extension AcState {
    /// Brings timers up to date at `now`: once a timer is due, the AC (or the bridge) has
    /// switched power, so the remote state follows and the timer is cleared, like a real
    /// remote's display.
    public func settled(now: Date = Date()) -> AcState {
        var s = self
        let due = [onTimerAt.map { ($0, true) }, offTimerAt.map { ($0, false) }]
            .compactMap { $0 }
            .sorted { $0.0 < $1.0 }
        for (at, power) in due where at <= now {
            s.power = power
            if power { s.onTimerAt = nil } else { s.offTimerAt = nil }
        }
        return s
    }

    /// Clamp to what `p` supports.
    public func fitted(to p: any DaikinProtocol) -> AcState {
        var s = self
        s.mode = p.modes.contains(mode) ? mode : p.modes[0]
        s.tempC = tempC.clamped(p.tempRange(s.mode))
        if !p.fans.contains(fan) {
            // Closest supported level; auto/quiet fall back to the first option.
            s.fan = fan.isLevel
                ? p.fans.min { abs($0.ordinal - fan.ordinal) < abs($1.ordinal - fan.ordinal) }!
                : p.fans[0]
        }
        s.swingV = swingV && p.supportsSwingV
        s.swingH = swingH && p.supportsSwingH
        return s
    }
}

extension Stored {
    /// The frame to send for the current state. Bridge-run timers must not also be programmed
    /// into the AC.
    public func frame(button: RemoteKey, now: Date = Date()) -> IrFrame {
        var wire = state
        if usesBridgeTimer {
            wire.onTimerAt = nil
            wire.offTimerAt = nil
        }
        return protocolValue.encode(wire, button: button, now: now)
    }

    /// The frame a bridge timer sends when it fires: the current settings with power set.
    public func timerFrame(power: Bool, now: Date = Date()) -> IrFrame {
        var wire = state
        wire.power = power
        wire.onTimerAt = nil
        wire.offTimerAt = nil
        return protocolValue.encode(wire, button: .power, now: now)
    }
}
