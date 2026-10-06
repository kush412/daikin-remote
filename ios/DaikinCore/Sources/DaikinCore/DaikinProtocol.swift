import Foundation

public protocol DaikinProtocol: Sendable {
    var id: String { get }
    var displayName: String { get }
    /// Remote / AC models known to use this protocol.
    var remotes: String { get }
    var modes: [Mode] { get }
    var fans: [Fan] { get }
    var supportsSwingV: Bool { get }
    var supportsSwingH: Bool { get }
    /// True if the AC itself runs the on/off timer; otherwise the bridge has to send it later.
    var nativeTimer: Bool { get }
    /// True if the power bit means "toggle" rather than an absolute on/off.
    var powerIsToggle: Bool { get }

    func tempRange(_ mode: Mode) -> ClosedRange<Int>

    /// Encode the full `state`. `now` is the phone's local time, used for the clock and timer
    /// fields; nil leaves them at their reset values (the golden tests rely on that).
    func encode(_ state: AcState, button: RemoteKey, now: Date?) -> IrFrame
}

extension DaikinProtocol {
    public var powerIsToggle: Bool { false }
}

/// Minutes since local midnight.
func minutesOfDay(_ date: Date) -> Int {
    let c = Calendar.current.dateComponents([.hour, .minute], from: date)
    return c.hour! * 60 + c.minute!
}

/// Whole minutes from `now` until `at`, rounded up.
func minutesUntil(_ at: Date, _ now: Date) -> Int {
    let ms = Int((at.timeIntervalSince(now) * 1000).rounded())
    return (ms + 59_999) / 60_000
}

/// Daikin day-of-week: SUN=1 … SAT=7 (the same numbering as Calendar's weekday).
func daikinDay(_ date: Date) -> Int { Calendar.current.component(.weekday, from: date) }

extension Fan {
    /// The value the ported `setFan()` setters take: 1–5, or 0xA (auto) / 0xB (quiet).
    var daikinCode: Int {
        switch self {
        case .auto: 0xA
        case .quiet: 0xB
        default: level
        }
    }
}

extension Mode {
    /// Daikin 3-bit mode codes shared by most protocols.
    var daikinCode: Int {
        switch self {
        case .auto: 0b000
        case .dry: 0b010
        case .cool: 0b011
        case .heat: 0b100
        case .fan: 0b110
        }
    }
}

let allModes = Mode.allCases
let allFans = Fan.allCases

/// Shared setFan() of the 280/2/152/160/216/312 families: 1–5 -> 3–7, auto/quiet pass through.
func daikinFanCode(_ fan: Int) -> Int {
    if fan == 0xA || fan == 0xB { return fan }
    if fan < 1 || fan > 5 { return 0xA }
    return 2 + fan
}

/// All supported protocols, most common first (the order the picker lists them in).
public enum Protocols {
    public static let all: [any DaikinProtocol] = [
        Daikin280(), Daikin2(), Daikin312(), Daikin216(), Daikin160(), Daikin152(), Daikin176(),
        Daikin128(), Daikin64(),
    ]

    public static func byId(_ id: String?) -> any DaikinProtocol {
        all.first { $0.id == id } ?? all[0]
    }
}
