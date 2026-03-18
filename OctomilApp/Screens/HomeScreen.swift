import SwiftUI
import Octomil

struct HomeScreen: View {
    @EnvironmentObject private var appState: AppState
    @State private var isRegistering = false
    @State private var errorMessage: String?
    @State private var modelToDelete: StoredModel?

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
                    if appState.storedModels.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("No models deployed yet")
                                .foregroundStyle(.secondary)
                            Text("Scan a QR code to get started.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    } else {
                        ForEach(appState.storedModels) { model in
                            NavigationLink {
                                destinationView(for: model)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(model.name)
                                            .font(.headline)
                                        Text("v\(model.version) \u{00B7} \(model.sizeString)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Label(model.capabilityLabel, systemImage: model.capabilityIcon)
                                        .font(.caption)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(capabilityColor(model.capability))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        .onDelete { indexSet in
                            if let index = indexSet.first {
                                modelToDelete = appState.storedModels[index]
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
            }
            .navigationTitle("Octomil")
            .alert("Delete Model", isPresented: Binding(
                get: { modelToDelete != nil },
                set: { if !$0 { modelToDelete = nil } }
            )) {
                Button("Delete", role: .destructive) {
                    if let model = modelToDelete {
                        appState.removeStoredModel(model)
                        modelToDelete = nil
                    }
                }
                Button("Cancel", role: .cancel) {
                    modelToDelete = nil
                }
            } message: {
                if let model = modelToDelete {
                    Text("Remove \(model.name) from this device?")
                }
            }
        }
    }

    @ViewBuilder
    private func destinationView(for model: StoredModel) -> some View {
        switch model.capability {
        case .transcription:
            TranscriptionScreen(model: model)
        case .chat:
            ChatScreen(model: model)
        case .keyboardPrediction:
            PredictionScreen(model: model)
        }
    }

    private func capabilityColor(_ capability: ModelCapability) -> Color {
        switch capability {
        case .transcription: return .purple
        case .chat: return .blue
        case .keyboardPrediction: return .orange
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
