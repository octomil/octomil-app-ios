import SwiftUI
import Octomil

struct ModelDetailScreen: View {
    let model: StoredModel

    var body: some View {
        List {
            Section("Model Info") {
                LabeledContent("Name", value: model.name)
                LabeledContent("Version", value: model.version)
                LabeledContent("Size", value: model.sizeString)
                LabeledContent("Runtime", value: model.runtime)
                LabeledContent("Capability", value: model.capabilityLabel)
                LabeledContent("Streaming", value: model.supportsStreaming ? "Yes" : "No")
                if let tps = model.tokensPerSecond {
                    LabeledContent("Tokens/sec", value: String(format: "%.1f", tps))
                }
            }

            Section("Try It Out") {
                NavigationLink {
                    destinationView(for: model)
                } label: {
                    Label("Open \(model.capabilityLabel)", systemImage: model.capabilityIcon)
                }
            }
        }
        .navigationTitle(model.name)
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
}
