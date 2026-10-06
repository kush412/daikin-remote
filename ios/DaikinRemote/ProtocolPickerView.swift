import DaikinCore
import SwiftUI

struct ProtocolPickerView: View {
    @Bindable var model: RemoteModel

    var body: some View {
        let canGoBack = model.stored.protocolId != nil
        List {
            Section {
                Text("Put the bridge where its IR LED can see the AC. Tap “Test ON” on each protocol, starting at the top, until the AC beeps and starts (Cool 24°C). Then tap “Use this”.\n\nIf you know your remote's model number (printed on its back), look for it below.")
                    .font(.subheadline)
                if let error = model.error {
                    Banner(text: error, color: .red, dismiss: model.dismissError) {
                        Button("Bridge settings") { model.showBridgeSetup = true }
                    }
                }
            }
            ForEach(Protocols.all.indices, id: \.self) { i in
                let p = Protocols.all[i]
                let current = p.id == model.stored.protocolId
                VStack(alignment: .leading, spacing: 8) {
                    Text(p.displayName + (current ? "  (in use)" : "")).font(.headline)
                    Text(p.remotes).font(.footnote).foregroundStyle(.secondary)
                    if p.powerIsToggle {
                        Text("Power is a toggle: Test ON and Test OFF both flip it.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        Button("Test ON") { model.test(p, power: true) }
                            .buttonStyle(.bordered)
                        Button("Test OFF") { model.test(p, power: false) }
                            .buttonStyle(.bordered)
                        Spacer()
                        Button("Use this") { model.choose(p) }
                            .buttonStyle(.borderedProminent)
                    }
                    .lineLimit(1)
                    .padding(.top, 2)
                }
                .padding(.vertical, 4)
                .listRowBackground(current ? Color.accentBlue.opacity(0.12) : nil)
            }
        }
        .navigationTitle("Find your AC's protocol")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            if canGoBack {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { model.screen = .remote }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { model.showBridgeSetup = true } label: {
                    BridgeStatus(online: model.bridgeOnline)
                }
            }
        }
    }
}
