import SwiftUI
import Octomil

struct ChatScreen: View {
    @EnvironmentObject private var appState: AppState
    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var streamingText = ""
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var generationTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if messages.isEmpty && !isGenerating {
                            emptyState
                        }

                        ForEach(Array(messages.enumerated()), id: \.offset) { index, message in
                            ChatBubble(message: message)
                                .id(index)
                        }

                        if !streamingText.isEmpty {
                            ChatBubble(message: .assistant(streamingText))
                                .id("streaming")
                        }

                        if isGenerating && streamingText.isEmpty {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Generating...")
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .id("loading")
                        }
                    }
                    .padding(.vertical, 8)
                }
                .onChange(of: messages.count) { _ in
                    withAnimation {
                        proxy.scrollTo(messages.count - 1, anchor: .bottom)
                    }
                }
                .onChange(of: streamingText) { _ in
                    withAnimation {
                        proxy.scrollTo("streaming", anchor: .bottom)
                    }
                }
            }

            Divider()

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
            }

            HStack(spacing: 8) {
                TextField("Message", text: $inputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .disabled(isGenerating)
                    .onSubmit { send() }

                if isGenerating {
                    Button {
                        cancelGeneration()
                    } label: {
                        Image(systemName: "stop.fill")
                            .foregroundStyle(.red)
                    }
                } else {
                    Button {
                        send()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .navigationTitle("Chat")
        .onDisappear {
            cancelGeneration()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Start a conversation")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Messages are processed on-device using your paired model.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard let client = appState.client else {
            errorMessage = "No client configured. Set device token in Settings."
            return
        }

        inputText = ""
        errorMessage = nil

        messages.append(.user(text))

        isGenerating = true
        streamingText = ""

        let chat = OctomilChat(
            modelName: appState.pairedModels.first?.name ?? "default",
            responses: client.responses
        )

        generationTask = Task {
            do {
                for try await chunk in chat.stream(text) {
                    if let content = chunk.choices.first?.delta.content {
                        await MainActor.run {
                            streamingText += content
                        }
                    }
                }

                await MainActor.run {
                    let fullText = streamingText
                    messages.append(.assistant(fullText))
                    streamingText = ""
                    isGenerating = false
                }
            } catch is CancellationError {
                await MainActor.run {
                    if !streamingText.isEmpty {
                        messages.append(.assistant(streamingText + " [cancelled]"))
                    }
                    streamingText = ""
                    isGenerating = false
                }
            } catch {
                await MainActor.run {
                    if !streamingText.isEmpty {
                        messages.append(.assistant(streamingText))
                    }
                    streamingText = ""
                    isGenerating = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
    }
}

// MARK: - Chat Bubble

private struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 48) }

            Text(message.content ?? "")
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(backgroundColor)
                .foregroundStyle(foregroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 16))

            if message.role != .user { Spacer(minLength: 48) }
        }
        .padding(.horizontal, 16)
    }

    private var backgroundColor: Color {
        message.role == .user ? .blue : Color(.systemGray5)
    }

    private var foregroundColor: Color {
        message.role == .user ? .white : .primary
    }
}
