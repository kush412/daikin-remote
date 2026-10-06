import DaikinCore
import Foundation
import Observation

enum Screen { case remote, picker }

/// Single source of truth for the remote. All bridge traffic goes through one serial queue, so
/// quick taps reach the AC in order.
@Observable
@MainActor
final class RemoteModel {
    private(set) var stored: Stored
    var screen: Screen
    var showBridgeSetup = false
    /// Increments on every transmission so the UI can flash a "sent" indicator.
    private(set) var sendCount = 0
    var error: String?
    var notice: String?
    /// nil until the first request finishes.
    private(set) var bridgeOnline: Bool?
    /// Ticks periodically so timer countdowns re-render.
    private(set) var now = Date()

    @ObservationIgnored private var queue: Task<Void, Never>?
    private static let storageKey = "stored"

    init() {
        var s = Stored()
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(Stored.self, from: data) {
            s = decoded
        }
        stored = s
        // First run: find the protocol before showing the remote.
        screen = s.protocolId == nil ? .picker : .remote
    }

    var protocolValue: any DaikinProtocol { stored.protocolValue }
    var state: AcState { stored.state }

    // MARK: - Buttons

    func power() { press(.power) { $0.power.toggle() } }
    func tempUp() { press(.temp) { $0.tempC += 1 } }
    func tempDown() { press(.temp) { $0.tempC -= 1 } }
    func mode(_ m: Mode) { press(.mode) { $0.mode = m } }
    func fan(_ f: Fan) { press(.fan) { $0.fan = f } }
    func swingV() { press(.swing) { $0.swingV.toggle() } }
    func swingH() { press(.swing) { $0.swingH.toggle() } }

    /// `minutes` from now, or nil to cancel.
    func setTimer(_ slot: TimerSlot, minutes: Int?) {
        let at = minutes.map { Date().addingTimeInterval(TimeInterval($0 * 60)) }
        press(.timer) { s in
            if slot == .on { s.onTimerAt = at } else { s.offTimerAt = at }
        }
    }

    func setBridgeTimer(_ enabled: Bool) {
        press(.timer, settings: { $0.bridgeTimer = enabled }) { _ in }
    }

    func setHost(_ host: String) {
        stored.bridgeHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        save()
        bridgeOnline = nil
        refresh()
    }

    /// Sends a Cool 24°C power on/off test frame with `p` without changing the saved state.
    func test(_ p: any DaikinProtocol, power: Bool) {
        let frame = p.encode(AcState(power: power, mode: .cool, tempC: 24, fan: .auto), button: .power, now: Date())
        transmit(frame)
    }

    func choose(_ p: any DaikinProtocol) {
        screen = .remote
        stored.protocolId = p.id
        stored.state = stored.state.fitted(to: p)
        save()
        syncBridgeTimers()
    }

    // MARK: - Timers and bridge status

    /// Called when the app comes to the foreground: applies due timers and checks the bridge.
    func refresh() {
        tick()
        let host = stored.bridgeHost
        // Bridge timers we believe are pending right now; if the bridge doesn't have them, it
        // restarted (power cut) and they are lost.
        let expected: (on: Date?, off: Date?) = stored.usesBridgeTimer ? (on: state.onTimerAt, off: state.offTimerAt) : (on: nil, off: nil)
        enqueue { [weak self] in
            do {
                let info = try await BridgeClient(host: host).info()
                self?.bridgeOnline = true
                self?.reconcile(info, expected: expected)
            } catch {
                self?.bridgeOnline = false
            }
        }
    }

    /// Re-renders countdowns and applies timers that are now due.
    func tick() {
        now = Date()
        let settled = stored.state.settled(now: now)
        if settled != stored.state {
            stored.state = settled
            save()
        }
    }

    func dismissError() { error = nil }
    func dismissNotice() { notice = nil }

    private func reconcile(_ info: BridgeInfo, expected: (on: Date?, off: Date?)) {
        var lost: [String] = []
        for slot in TimerSlot.allCases {
            let mine = slot == .on ? expected.on : expected.off
            let current = slot == .on ? state.onTimerAt : state.offTimerAt
            // Ignore timers that are due (they fired) or were changed since the request.
            guard let at = mine, at == current, at.timeIntervalSinceNow > 5, info.remaining(slot) == nil else { continue }
            if slot == .on { stored.state.onTimerAt = nil } else { stored.state.offTimerAt = nil }
            lost.append(slot.rawValue.uppercased())
        }
        if !lost.isEmpty {
            save()
            notice = "The bridge restarted, so the \(lost.joined(separator: " and ")) timer was lost. Set it again."
        }
    }

    // MARK: - Sending

    /// Applies `change` to the latest state, saves it and transmits it.
    private func press(_ button: RemoteKey, settings: (inout Stored) -> Void = { _ in }, change: (inout AcState) -> Void) {
        var s = stored
        settings(&s)
        var next = s.state.settled()
        change(&next)
        s.state = next.fitted(to: s.protocolValue)
        stored = s
        save()
        transmit(s.frame(button: button))
        // Bridge timers carry a copy of the settings, so refresh them after any change.
        if button == .timer || (s.usesBridgeTimer && (s.state.onTimerAt != nil || s.state.offTimerAt != nil)) {
            syncBridgeTimers()
        }
    }

    private func transmit(_ frame: IrFrame) {
        sendCount += 1
        let host = stored.bridgeHost
        enqueue { [weak self] in
            do {
                try await BridgeClient(host: host).send(frame)
                self?.bridgeOnline = true
                self?.error = nil
            } catch {
                self?.bridgeOnline = false
                self?.error = error.localizedDescription
            }
        }
    }

    private func syncBridgeTimers() {
        let s = stored
        let host = s.bridgeHost
        let plan: [(TimerSlot, Date?, IrFrame?)] = TimerSlot.allCases.map { slot in
            let at = s.usesBridgeTimer ? (slot == .on ? s.state.onTimerAt : s.state.offTimerAt) : nil
            return (slot, at, at.map { _ in s.timerFrame(power: slot.power) })
        }
        enqueue { [weak self] in
            let client = BridgeClient(host: host)
            do {
                for (slot, at, frame) in plan {
                    if let at, let frame {
                        let seconds = max(1, Int(at.timeIntervalSinceNow.rounded(.up)))
                        try await client.setTimer(slot, inSeconds: seconds, frame: frame)
                    } else {
                        try await client.cancelTimer(slot)
                    }
                }
            } catch {
                self?.error = "Couldn't update the bridge timer: \(error.localizedDescription)"
            }
        }
    }

    private func enqueue(_ op: @escaping @MainActor () async -> Void) {
        let previous = queue
        queue = Task { @MainActor in
            await previous?.value
            await op()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
