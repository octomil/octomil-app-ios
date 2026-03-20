import SwiftUI
import Octomil
import OctomilClient

@main
struct CompanionApp: App {
    @StateObject private var appState = AppState()

    init() {
        ensureEnginesRegistered()
    }

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
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                guard let url = activity.webpageURL else { return }
                handleDeepLink(url)
            }
            .task {
                await appState.startLocalServer()
                appState.startAdvertising()
                await appState.recoverMissingModels()
            }
        }
    }

    /// Handle deep links: octomil://pair?token=X&host=Y (or code/server variants)
    private func handleDeepLink(_ url: URL) {
        guard let result = DeepLinkHandler.parse(url) else { return }

        if let host = result.host {
            appState.serverURL = host
            appState.initializeClient()
        }

        appState.pendingPairingCode = result.pairingCode
        appState.showPairingSheet = true
        appState.selectedTab = .pair
    }
}
