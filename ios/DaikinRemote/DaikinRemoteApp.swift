import SwiftUI

@main
struct DaikinRemoteApp: App {
    @State private var model = RemoteModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .tint(.accentBlue)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { model.refresh() }
                }
        }
    }
}

struct RootView: View {
    @Bindable var model: RemoteModel

    var body: some View {
        NavigationStack {
            switch model.screen {
            case .picker: ProtocolPickerView(model: model)
            case .remote: RemoteView(model: model)
            }
        }
        .sheet(isPresented: $model.showBridgeSetup) {
            BridgeSetupView(model: model)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: model.sendCount)
        .task {
            // Re-render countdowns and apply timers that came due.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                model.tick()
            }
        }
    }
}

extension Color {
    static let accentBlue = Color(red: 0.04, green: 0.49, blue: 0.76)
}
