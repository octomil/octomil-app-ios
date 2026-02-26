import SwiftUI
import OctomilClient
import OctomilUI

struct PairScreen: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationStack {
            Group {
                if let client = appState.client {
                    PairingView(client: client) { model in
                        appState.addModel(model)
                        appState.showPairingSheet = false
                        appState.pendingPairingCode = nil
                    }
                } else {
                    ContentUnavailableView(
                        "Not Configured",
                        systemImage: "gear",
                        description: Text("Set your API key in Settings before pairing.")
                    )
                }
            }
            .navigationTitle("Pair Device")
            .onAppear {
                // Auto-trigger pairing if code was received (deep link or local server)
                if let code = appState.pendingPairingCode {
                    appState.pendingPairingCode = nil
                    // The PairingView handles auto-connect via its initializer
                }
            }
        }
    }
}
