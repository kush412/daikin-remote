import DaikinCore
import SwiftUI

struct RemoteView: View {
    @Bindable var model: RemoteModel
    @State private var timerSlot: TimerSlot?

    var body: some View {
        let s = model.state
        let p = model.protocolValue
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                DisplayCard(state: s, now: model.now, sendCount: model.sendCount)

                if let notice = model.notice {
                    Banner(text: notice, color: .orange, dismiss: model.dismissNotice)
                }
                if let error = model.error {
                    Banner(text: error, color: .red, dismiss: model.dismissError) {
                        Button("Bridge settings") { model.showBridgeSetup = true }
                    }
                }

                // Power + temperature
                HStack(spacing: 14) {
                    Button(action: model.power) {
                        Image(systemName: "power")
                            .font(.system(size: 34, weight: .semibold))
                            .frame(width: 84, height: 84)
                            .foregroundStyle(s.power ? Color.white : Color.secondary)
                            .background(Circle().fill(s.power ? Color.accentBlue : Color(.tertiarySystemFill)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Power")
                    .animation(.easeInOut(duration: 0.2), value: s.power)

                    let range = p.tempRange(s.mode)
                    let tempEnabled = s.mode != .fan
                    BigButton(symbol: "minus", enabled: tempEnabled && s.tempC > range.lowerBound, action: model.tempDown)
                    BigButton(symbol: "plus", enabled: tempEnabled && s.tempC < range.upperBound, action: model.tempUp)
                }
                if p.powerIsToggle {
                    Hint("This protocol toggles power. If the AC is out of sync with the app, press Power again.")
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionTitle("Mode")
                    Choices(options: p.modes, selected: s.mode, label: \.label, onSelect: model.mode)
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionTitle("Fan speed  ·  \(fanText(s.fan))")
                    FanSelector(options: p.fans, selected: s.fan, onSelect: model.fan)
                }

                if p.supportsSwingV || p.supportsSwingH {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionTitle("Swing")
                        HStack(spacing: 8) {
                            if p.supportsSwingV { ToggleChip(label: "↕ Up/down", on: s.swingV, action: model.swingV) }
                            if p.supportsSwingH { ToggleChip(label: "↔ Left/right", on: s.swingH, action: model.swingH) }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle("Timer")
                    HStack(spacing: 8) {
                        TimerButton(label: "ON", at: s.onTimerAt, now: model.now) { timerSlot = .on }
                        TimerButton(label: "OFF", at: s.offTimerAt, now: model.now) { timerSlot = .off }
                    }
                    if p.nativeTimer && !p.powerIsToggle {
                        Toggle(isOn: Binding(get: { model.stored.bridgeTimer }, set: model.setBridgeTimer)) {
                            Text("Run timer on the bridge instead of the AC").font(.subheadline)
                        }
                    }
                    if model.stored.usesBridgeTimer {
                        Hint(p.nativeTimer
                            ? "The bridge sends the command when it's due. Keep it powered."
                            : "This AC has no built-in IR timer, so the bridge sends the command when it's due. Keep it powered.")
                    } else {
                        Hint("The timer is stored in the AC; the phone can be put away.")
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .navigationTitle("Daikin Remote")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { model.showBridgeSetup = true } label: {
                    BridgeStatus(online: model.bridgeOnline)
                }
            }
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text("Daikin Remote").font(.headline)
                    Text(p.displayName).font(.caption).foregroundStyle(.secondary)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Protocol") { model.screen = .picker }
            }
        }
        .sheet(item: $timerSlot) { slot in
            TimerSheet(slot: slot) { minutes in
                timerSlot = nil
                model.setTimer(slot, minutes: minutes)
            }
            .presentationDetents([.medium])
        }
    }
}

// MARK: - Display

private struct DisplayCard: View {
    let state: AcState
    let now: Date
    let sendCount: Int
    @State private var flash = false

    private var bigText: String {
        switch state.mode {
        case .fan: return "Fan"
        case .dry: return "Dry"
        default: return "\(state.tempC)°"
        }
    }

    private var summary: String {
        let parts: [String?] = [state.mode.label, "Fan: " + fanText(state.fan), state.swingV ? "↕" : nil, state.swingH ? "↔" : nil]
        return parts.compactMap { $0 }.joined(separator: "  ·  ")
    }

    private var timers: String {
        var parts: [String] = []
        if let at = state.onTimerAt { parts.append("On at \(clockText(at)) (\(countdown(at, now)))") }
        if let at = state.offTimerAt { parts.append("Off at \(clockText(at)) (\(countdown(at, now)))") }
        return parts.joined(separator: "  ·  ")
    }

    var body: some View {
        let s = state
        VStack(spacing: 4) {
            Text(s.power ? "ON" : "OFF").font(.subheadline.weight(.semibold))
            Text(bigText)
                .font(.system(size: 88, weight: .light))
                .contentTransition(.numericText())
            Text(summary)
                .font(.headline)
                .multilineTextAlignment(.center)
            if !timers.isEmpty {
                Text(timers).font(.subheadline)
            }
        }
        .foregroundStyle(Color.accentBlue)
        .opacity(s.power ? 1 : 0.45)
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.accentBlue.opacity(0.12)))
        .overlay(alignment: .topTrailing) {
            // Brief "sending" dot each time a frame goes out.
            Circle().fill(.orange).frame(width: 10, height: 10).padding(14).opacity(flash ? 1 : 0)
        }
        .animation(.easeInOut(duration: 0.2), value: s)
        .onChange(of: sendCount) {
            flash = true
            Task {
                try? await Task.sleep(for: .milliseconds(250))
                flash = false
            }
        }
    }
}

// MARK: - Controls

private struct BigButton: View {
    let symbol: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: 72)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 18))
        .disabled(!enabled)
    }
}

private struct Choices<T: Hashable>: View {
    let options: [T]
    let selected: T
    let label: KeyPath<T, String>
    let onSelect: (T) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.self) { o in
                Chip(label: o[keyPath: label], on: o == selected) { onSelect(o) }
            }
        }
    }
}

private struct Chip: View {
    let label: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 40)
        }
        .foregroundStyle(on ? .white : Color.accentBlue)
        .background(Capsule().fill(on ? Color.accentBlue : .clear))
        .overlay(Capsule().stroke(Color.accentBlue.opacity(on ? 0 : 0.5)))
        .buttonStyle(.plain)
    }
}

private struct ToggleChip: View {
    let label: String
    let on: Bool
    let action: () -> Void

    var body: some View { Chip(label: label, on: on, action: action) }
}

/// Auto / Quiet buttons plus five ascending bars like a signal meter: bars up to the chosen
/// speed are filled, and the number under each bar is the speed it selects.
private struct FanSelector: View {
    let options: [Fan]
    let selected: Fan
    let onSelect: (Fan) -> Void

    var body: some View {
        let special = options.filter { !$0.isLevel }
        let levels = options.filter(\.isLevel)
        let chosen = levels.contains(selected) ? selected.level : 0
        VStack(spacing: 12) {
            if !special.isEmpty {
                Choices(options: special, selected: selected, label: \.label, onSelect: onSelect)
            }
            if !levels.isEmpty {
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(levels, id: \.self) { f in
                        Button { onSelect(f) } label: {
                            VStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(f.level <= chosen ? Color.accentBlue : Color(.tertiarySystemFill))
                                    .frame(height: CGFloat(14 + f.level * 12))
                                Text(f.label)
                                    .fontWeight(f == selected ? .bold : .regular)
                                    .foregroundStyle(f == selected ? Color.accentBlue : .secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 96, alignment: .bottom)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct TimerButton: View {
    let label: String
    let at: Date?
    let now: Date
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(at.map { "\(label) at \(clockText($0))" } ?? "\(label) timer").lineLimit(1)
                Text(at.map { countdown($0, now) } ?? "not set").font(.caption)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
        }
        .foregroundStyle(at != nil ? .white : Color.accentBlue)
        .background(RoundedRectangle(cornerRadius: 14).fill(at != nil ? Color.accentBlue : .clear))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.accentBlue.opacity(at != nil ? 0 : 0.5)))
        .buttonStyle(.plain)
    }
}

private struct TimerSheet: View {
    let slot: TimerSlot
    let onPick: (Int?) -> Void
    private let options = [15, 30, 60, 90, 120, 180, 240, 300, 360, 480, 600, 720]

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(options, id: \.self) { m in
                        Button(m < 60 ? "\(m)m" : m % 60 == 0 ? "\(m / 60)h" : "\(m / 60).5h") { onPick(m) }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                    }
                }
                Button("Cancel timer", role: .destructive) { onPick(nil) }
                Spacer()
            }
            .padding()
            .navigationTitle(slot == .on ? "Turn ON after…" : "Turn OFF after…")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Small pieces

struct Banner<Actions: View>: View {
    let text: String
    let color: Color
    let dismiss: () -> Void
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
            HStack {
                actions
                Spacer()
                Button("OK", action: dismiss)
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(color.opacity(0.15)))
    }
}

extension Banner where Actions == EmptyView {
    init(text: String, color: Color, dismiss: @escaping () -> Void) {
        self.init(text: text, color: color, dismiss: dismiss) { EmptyView() }
    }
}

struct BridgeStatus: View {
    let online: Bool?

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(online == true ? Color.green : online == false ? Color.red : Color.gray)
                .frame(width: 8, height: 8)
            Text("Bridge").font(.subheadline)
        }
    }
}

struct Hint: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.footnote).foregroundStyle(.secondary)
    }
}

private struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
    }
}

func fanText(_ f: Fan) -> String {
    switch f {
    case .auto: "Auto"
    case .quiet: "Quiet"
    default: "Speed \(f.level) of 5"
    }
}

func clockText(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }

/// "in 1h 05m" / "in 4m" until `at`.
func countdown(_ at: Date, _ now: Date) -> String {
    let mins = max(0, Int((at.timeIntervalSince(now) / 60).rounded(.up)))
    return mins >= 60 ? "in \(mins / 60)h \(String(format: "%02d", mins % 60))m" : "in \(mins)m"
}
