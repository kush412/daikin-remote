import Foundation

public enum Mode: String, CaseIterable, Codable, Sendable {
    case auto, cool, dry, heat, fan

    public var label: String {
        switch self {
        case .auto: "Auto"
        case .cool: "Cool"
        case .dry: "Dry"
        case .heat: "Heat"
        case .fan: "Fan"
        }
    }
}

/// Fan levels as on Daikin remotes: Auto, Quiet (silent indoor unit) and 1–5 bars.
public enum Fan: String, CaseIterable, Codable, Sendable {
    case auto, quiet, l1, l2, l3, l4, l5

    public var label: String {
        switch self {
        case .auto: "Auto"
        case .quiet: "Quiet"
        default: String(level)
        }
    }

    public var ordinal: Int { Fan.allCases.firstIndex(of: self)! }

    /// l1 -> 1 … l5 -> 5; meaningless for auto/quiet.
    public var level: Int { ordinal - 1 }

    public var isLevel: Bool { self != .auto && self != .quiet }
}

/// The button pressed for this frame. Some protocols encode it (power toggle, mode button).
public enum RemoteKey: CaseIterable, Sendable {
    case power, mode, temp, fan, swing, timer, test
}

/// Complete remote state; every frame encodes all of it, like a real Daikin remote.
public struct AcState: Codable, Equatable, Sendable {
    public var power = false
    public var mode = Mode.cool
    public var tempC = 25
    public var fan = Fan.auto
    public var swingV = false
    public var swingH = false
    /// When the AC should switch on, or nil.
    public var onTimerAt: Date?
    /// When the AC should switch off, or nil.
    public var offTimerAt: Date?

    public init(
        power: Bool = false, mode: Mode = .cool, tempC: Int = 25, fan: Fan = .auto,
        swingV: Bool = false, swingH: Bool = false, onTimerAt: Date? = nil, offTimerAt: Date? = nil
    ) {
        self.power = power
        self.mode = mode
        self.tempC = tempC
        self.fan = fan
        self.swingV = swingV
        self.swingH = swingH
        self.onTimerAt = onTimerAt
        self.offTimerAt = offTimerAt
    }
}
