import SwiftUI
import OctomilClient

struct HomeScreen: View {
    @EnvironmentObject private var appState: AppState
    @State private var isRegistering = false
    @State private var errorMessage: String?
    @State private var cacheSize: String = "Calculating..."

    var body: some View {
        NavigationStack {
            List {
                Section("Device") {
                    if let client = appState.client {
                        let caps = client.deviceCapabilities
                        LabeledContent("Model", value: caps.model)
                        LabeledContent("CPU", value: caps.cpuArchitecture)
                        LabeledContent("OS", value: caps.osVersion)
                        LabeledContent("RAM", value: "\(caps.totalMemoryMb) MB")
                        LabeledContent("Neural Engine", value: caps.npuAvailable ? "Available" : "Not Available")
                        if let tops = caps.npuTops {
                            LabeledContent("NPU TOPS", value: String(format: "%.1f", tops))
                        }
                    } else {
                        ContentUnavailableView(
                            "Not Configured",
                            systemImage: "gear",
                            description: Text("Set your API key in Settings to get started.")
                        )
                    }
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
                    }

                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("Downloaded Models") {
                    if appState.downloadedModels.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("No models deployed yet")
                                .foregroundStyle(.secondary)
                            Text("Deploy a model with `octomil deploy <model> --phone`")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    } else {
                        ForEach(appState.downloadedModels, id: \.modelId) { model in
                            NavigationLink {
                                ModelDetailScreen(model: model)
                            } label: {
                                HStack {
                                    modalityIcon(for: model)
                                        .foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(model.modelId)
                                            .font(.headline)
                                        Text("v\(model.version) \u{00B7} \(model.format)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }

                Section("Network") {
                    LabeledContent("Device Name", value: appState.deviceName)
                    if appState.localPort > 0 {
                        LabeledContent("Local Server", value: "Port \(appState.localPort)")
                    }
                }

                Section("Cache") {
                    LabeledContent("Size", value: cacheSize)
                }
            }
            .navigationTitle("Octomil")
            .task {
                await updateCacheSize()
            }
        }
    }

    @ViewBuilder
    private func modalityIcon(for model: OctomilModel) -> some View {
        switch model.format.lowercased() {
        case let f where f.contains("vision"):
            Image(systemName: "eye")
        case let f where f.contains("audio"):
            Image(systemName: "waveform")
        default:
            Image(systemName: "text.bubble")
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

    private func updateCacheSize() async {
        guard let client = appState.client else { return }
        do {
            let bytes = try await client.cacheSize()
            cacheSize = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        } catch {
            cacheSize = "Unknown"
        }
    }
}
