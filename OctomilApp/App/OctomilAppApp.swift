import SwiftUI
import OctomilClient
import OctomilUI

@main
struct OctomilAppApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            TabView(selection: $appState.selectedTab) {
                HomeScreen()
                    .tabItem {
                        Label("Home", systemImage: "house")
                    }
                    .tag(AppTab.home)

                PairScreen()
                    .tabItem {
                        Label("Pair", systemImage: "qrcode.viewfinder")
                    }
                    .tag(AppTab.pair)

                SettingsScreen()
                    .tabItem {
                        Label("Settings", systemImage: "gear")
                    }
                    .tag(AppTab.settings)
            }
            .environmentObject(appState)
            .onOpenURL { url in
                handleDeepLink(url)
            }
            .task {
                appState.startLocalServer()
                appState.startAdvertising()
            }
        }
    }

    /// Handle deep links: octomil://pair?token=X&host=Y (or code/server variants)
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "octomil", url.host == "pair" else { return }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return
        }

        let items = components.queryItems ?? []
        // Support both token/code and host/server for backwards compat
        let code = items.first(where: { $0.name == "token" })?.value
            ?? items.first(where: { $0.name == "code" })?.value
        let host = items.first(where: { $0.name == "host" })?.value
            ?? items.first(where: { $0.name == "server" })?.value

        guard let pairingCode = code else { return }

        if let host, !host.isEmpty {
            appState.serverURL = host
            appState.initializeClient()
        }

        appState.pendingPairingCode = pairingCode
        appState.showPairingSheet = true
        appState.selectedTab = .pair
    }
}

enum AppTab {
    case home, pair, settings
}
