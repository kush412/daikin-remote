import SwiftUI

struct BridgeSetupView: View {
    @Bindable var model: RemoteModel
    @Environment(\.dismiss) private var dismiss
    @State private var host = ""
    @State private var status: String?
    @State private var checking = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("daikin-ir.local or 192.168.1.50", text: $host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .onSubmit(check)
                    Button(action: check) {
                        HStack {
                            Text("Save and test connection")
                            if checking { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(checking || host.trimmingCharacters(in: .whitespaces).isEmpty)
                    if let status {
                        Text(status).font(.footnote)
                    }
                } header: {
                    Text("Bridge address")
                } footer: {
                    Text("iPhones have no IR blaster, so the app sends each command over Wi-Fi to an ESP32/ESP8266 IR bridge, which flashes it to the AC. The bridge prints its address on the serial monitor when it connects.")
                }
            }
            .navigationTitle("IR bridge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { host = model.stored.bridgeHost }
        }
    }

    @MainActor private func check() {
        let h = host.trimmingCharacters(in: .whitespacesAndNewlines)
        model.setHost(h)
        checking = true
        status = nil
        Task {
            do {
                let info = try await BridgeClient(host: h).info()
                status = "✅ Connected to \(info.device) v\(info.version)."
            } catch {
                status = "❌ \(error.localizedDescription)"
            }
            checking = false
        }
    }
}
