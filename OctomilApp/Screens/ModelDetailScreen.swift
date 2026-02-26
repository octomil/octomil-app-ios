import SwiftUI
import Octomil

struct ModelDetailScreen: View {
    let model: PairedModelInfo

    var body: some View {
        List {
            Section("Model Info") {
                LabeledContent("Name", value: model.name)
                LabeledContent("Version", value: model.version)
                LabeledContent("Size", value: model.sizeString)
                LabeledContent("Runtime", value: model.runtime)
                if let tps = model.tokensPerSecond {
                    LabeledContent("Tokens/sec", value: String(format: "%.1f", tps))
                }
                if let modality = model.modality {
                    LabeledContent("Modality", value: modality)
                }
            }

            Section("Try It Out") {
                NavigationLink {
                    TryItOutScreen(modelInfo: model)
                } label: {
                    Label("Open Interactive Demo", systemImage: "play.fill")
                }
            }
        }
        .navigationTitle(model.name)
    }
}
