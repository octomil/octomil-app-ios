import SwiftUI
import OctomilClient

struct PairScreen: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationStack {
            Group {
                if let code = appState.pendingPairingCode {
                    PairingScreen(
                        token: code,
                        host: appState.serverURL,
                        onTryModel: { modelInfo in
                            appState.addPairedModel(modelInfo)
                            appState.showPairingSheet = false
                            appState.pendingPairingCode = nil
                        }
                    )
                } else if appState.client != nil {
                    VStack(spacing: 16) {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("Ready to Pair")
                            .font(.title2.bold())
                        Text("Scan a QR code or run\n`octomil deploy <model> --phone`\nto pair.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "gear")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("Not Configured")
                            .font(.title2.bold())
                        Text("Set your device token in Settings before pairing.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                }
            }
            .navigationTitle("Pair Device")
        }
    }
}
