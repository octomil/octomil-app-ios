import SwiftUI
import OctomilClient

struct SettingsScreen: View {
    @EnvironmentObject private var appState: AppState
    @State private var showClearCacheAlert = false
    @State private var statusMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("API Configuration") {
                    TextField("Device Token", text: $appState.deviceToken)
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
                    .disabled(appState.deviceToken.isEmpty || appState.orgId.isEmpty)
                }

                Section("Device") {
                    TextField("Device Name", text: $appState.deviceName)
                        .autocorrectionDisabled()
                }

                Section("Cache") {
                    Button("Clear Model Cache", role: .destructive) {
                        showClearCacheAlert = true
                    }
                }

                Section("Device Info") {
                    LabeledContent("Chip", value: deviceModel)
                    LabeledContent("RAM", value: "\(ProcessInfo.processInfo.physicalMemory / (1024 * 1024)) MB")
                    LabeledContent("OS", value: UIDevice.current.systemVersion)
                }

                Section("About") {
                    LabeledContent("App Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
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
        }
    }

    private var deviceModel: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0) ?? UIDevice.current.model
            }
        }
    }

    private func clearCache() {
        Task {
            guard let client = appState.client else { return }
            do {
                try await client.clearCache()
                appState.pairedModels.removeAll()
                statusMessage = "Cache cleared"
            } catch {
                statusMessage = "Failed: \(error.localizedDescription)"
            }
        }
    }
}
