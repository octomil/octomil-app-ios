import SwiftUI
import Octomil

struct PredictionScreen: View {
    @EnvironmentObject private var appState: AppState
    @State private var inputText = "The weather today is"
    @State private var suggestions: [String] = []
    @State private var isPredicting = false
    @State private var errorMessage: String?
    @State private var statusMessage = "Type text and tap Predict to get next-word suggestions."

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Input Text")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Enter text...", text: $inputText, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(2...6)
                    }
                    .padding(.horizontal, 16)

                    if !suggestions.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Suggestions")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            FlowLayout(spacing: 8) {
                                ForEach(suggestions, id: \.self) { word in
                                    Button {
                                        appendSuggestion(word)
                                    } label: {
                                        Text(word)
                                            .font(.subheadline)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(Color(.systemGray5))
                                            .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 16)
                    }

                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                }
                .padding(.vertical, 16)
            }

            Divider()

            HStack(spacing: 12) {
                Button {
                    predict()
                } label: {
                    HStack {
                        if isPredicting {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text("Predict Next")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPredicting)

                Button("Clear") {
                    suggestions = []
                    inputText = ""
                    statusMessage = "Type text and tap Predict to get next-word suggestions."
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .navigationTitle("Prediction")
    }

    private func appendSuggestion(_ word: String) {
        if inputText.hasSuffix(" ") || inputText.isEmpty {
            inputText += word
        } else {
            inputText += " " + word
        }
        suggestions = []
    }

    private func predict() {
        guard let client = appState.client else {
            errorMessage = "No client configured. Set device token in Settings."
            return
        }

        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        errorMessage = nil
        isPredicting = true
        statusMessage = "Predicting..."

        Task {
            do {
                let result = try await client.text.predictions.create(input: text, n: 5)
                await MainActor.run {
                    suggestions = result.predictions.map(\.text)
                    isPredicting = false
                    if result.predictions.isEmpty {
                        statusMessage = "No suggestions generated. Try different input text."
                    } else {
                        statusMessage = "Tap a suggestion to append it."
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isPredicting = false
                    statusMessage = "Prediction failed. Check that a model is loaded."
                }
            }
        }
    }
}

// MARK: - Flow Layout for suggestion chips

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: ProposedViewSize(result.sizes[index])
            )
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> LayoutResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var sizes: [CGSize] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            sizes.append(size)

            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }

            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        let totalHeight = y + rowHeight
        return LayoutResult(
            size: CGSize(width: maxWidth, height: totalHeight),
            positions: positions,
            sizes: sizes
        )
    }

    private struct LayoutResult {
        let size: CGSize
        let positions: [CGPoint]
        let sizes: [CGSize]
    }
}
