import SwiftUI
import OctomilClient

struct HomeScreen: View {
    @EnvironmentObject private var appState: AppState
    @State private var isRegistering = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Device") {
                    LabeledContent("Model", value: deviceModel)
                    #if arch(arm64)
                    LabeledContent("CPU", value: "arm64")
                    #else
                    LabeledContent("CPU", value: "x86_64")
                    #endif
                    LabeledContent("OS", value: UIDevice.current.systemVersion)
                    LabeledContent("RAM", value: "\(ProcessInfo.processInfo.physicalMemory / (1024 * 1024)) MB")
                }

                Section("Status") {
                    if appState.isRegistered {
                        Label("Registered", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else if appState.client != nil {
                        Button {
                            register()
                        } label: {
                            if isRegistering {
                                HStack {
                                    ProgressView()
                                    Text("Registering...")
                                }
                            } else {
                                Label("Register Device", systemImage: "person.badge.plus")
                            }
                        }
                        .disabled(isRegistering)
                    } else {
                        Text("Set device token in Settings to get started.")
                            .foregroundStyle(.secondary)
                    }

                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("Paired Models") {
                    if appState.pairedModels.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("No models deployed yet")
                                .foregroundStyle(.secondary)
                            Text("Deploy a model with `octomil deploy <model> --phone`")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    } else {
                        ForEach(appState.pairedModels, id: \.name) { model in
                            NavigationLink {
                                ModelDetailScreen(model: model)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(model.name)
                                        .font(.headline)
                                    Text("v\(model.version) \u{00B7} \(model.runtime)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section("Features") {
                    NavigationLink {
                        ChatScreen()
                    } label: {
                        Label("Chat", systemImage: "bubble.left.and.bubble.right")
                    }

                    NavigationLink {
                        TranscriptionScreen()
                    } label: {
                        Label("Transcription", systemImage: "waveform")
                    }

                    NavigationLink {
                        PredictionScreen()
                    } label: {
                        Label("Prediction", systemImage: "text.cursor")
                    }
                }

                Section("Network") {
                    LabeledContent("Device Name", value: appState.deviceName)
                    if appState.localPort > 0 {
                        LabeledContent("Local Server", value: "Port \(appState.localPort)")
                    }
                }
            }
            .navigationTitle("Octomil")
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

    private func register() {
        isRegistering = true
        errorMessage = nil
        Task {
            do {
                try await appState.register()
            } catch {
                errorMessage = error.localizedDescription
            }
            isRegistering = false
        }
    }
}
