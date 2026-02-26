import SwiftUI
import OctomilClient

struct ModelDetailScreen: View {
    let model: OctomilModel

    @State private var inferenceResult: String?
    @State private var isRunning = false
    @State private var latencyMs: Double?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section("Model Info") {
                LabeledContent("ID", value: model.modelId)
                LabeledContent("Version", value: model.version)
                LabeledContent("Format", value: model.format)
                if let url = model.localURL {
                    LabeledContent("Path", value: url.lastPathComponent)
                }
            }

            Section("Inference") {
                Button {
                    runInference()
                } label: {
                    if isRunning {
                        HStack {
                            ProgressView()
                            Text("Running...")
                        }
                    } else {
                        Label("Test Inference", systemImage: "play.fill")
                    }
                }
                .disabled(isRunning)

                if let result = inferenceResult {
                    Text(result)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }

                if let latency = latencyMs {
                    LabeledContent("Latency", value: String(format: "%.1f ms", latency))
                }

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(model.modelId)
    }

    private func runInference() {
        isRunning = true
        errorMessage = nil
        inferenceResult = nil

        Task {
            do {
                let start = CFAbsoluteTimeGetCurrent()
                if let runner = model.runner {
                    let result = try await runner.run(input: [:])
                    let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
                    inferenceResult = String(describing: result)
                    latencyMs = elapsed
                } else {
                    errorMessage = "No runner loaded for this model"
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isRunning = false
        }
    }
}
