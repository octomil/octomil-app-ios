import SwiftUI
import OctomilClient

struct SettingsScreen: View {
    @EnvironmentObject private var appState: AppState
    @State private var showClearCacheAlert = false
    @State private var showLogoutAlert = false
    @State private var cacheSize: String = "..."
    @State private var statusMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("API Configuration") {
                    TextField("API Key", text: $appState.apiKey)
                        .textContentType(.none)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    TextField("Organization ID", text: $appState.orgId)
                        .textContentType(.organizationName)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    TextField("Server URL", text: $appState.serverURL)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    Button("Save & Reconnect") {
                        appState.initializeClient()
                        statusMessage = "Client reconfigured"
                    }
                    .disabled(appState.apiKey.isEmpty || appState.orgId.isEmpty)
                }

                Section("Device") {
                    TextField("Device Name", text: $appState.deviceName)
                        .autocorrectionDisabled()
                }

                Section("Cache") {
                    LabeledContent("Size", value: cacheSize)
                    Button("Clear Model Cache", role: .destructive) {
                        showClearCacheAlert = true
                    }
                }

                Section("Device Info") {
                    if let client = appState.client {
                        let caps = client.deviceCapabilities
                        LabeledContent("Chip", value: caps.model)
                        LabeledContent("RAM", value: "\(caps.totalMemoryMb) MB")
                        LabeledContent("OS", value: caps.osVersion)
                        LabeledContent("NPU", value: caps.npuAvailable ? "Available" : "Not Available")
                    }
                }

                Section("Account") {
                    if appState.isRegistered {
                        Button("Logout", role: .destructive) {
                            showLogoutAlert = true
                        }
                    } else {
                        Text("Not registered")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("About") {
                    LabeledContent("App Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                    LabeledContent("SDK Version", value: "1.0.0")
                    LabeledContent("Platform", value: "iOS")
                }

                if let status = statusMessage {
                    Section {
                        Text(status)
                            .foregroundStyle(.green)
                    }
                }
            }
            .navigationTitle("Settings")
            .alert("Clear Cache?", isPresented: $showClearCacheAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Clear", role: .destructive) { clearCache() }
            } message: {
                Text("This will remove all downloaded models.")
            }
            .alert("Logout?", isPresented: $showLogoutAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Logout", role: .destructive) { logout() }
            } message: {
                Text("This will revoke device authentication.")
            }
            .task {
                await updateCacheSize()
            }
        }
    }

    private func clearCache() {
        Task {
            guard let client = appState.client else { return }
            do {
                try await client.clearCache()
                appState.downloadedModels.removeAll()
                await updateCacheSize()
                statusMessage = "Cache cleared"
            } catch {
                statusMessage = "Failed: \(error.localizedDescription)"
            }
        }
    }

    private func logout() {
        Task {
            guard let client = appState.client else { return }
            do {
                try await client.logout(reason: "user_initiated")
                appState.isRegistered = false
                appState.downloadedModels.removeAll()
                statusMessage = "Logged out"
            } catch {
                statusMessage = "Logout failed: \(error.localizedDescription)"
            }
        }
    }

    private func updateCacheSize() async {
        guard let client = appState.client else {
            cacheSize = "N/A"
            return
        }
        do {
            let bytes = try await client.cacheSize()
            cacheSize = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        } catch {
            cacheSize = "Unknown"
        }
    }
}
