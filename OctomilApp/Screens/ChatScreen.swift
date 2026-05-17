import PhotosUI
import SwiftUI
import Octomil

struct ChatScreen: View {
    @EnvironmentObject private var appState: AppState
    let model: StoredModel

    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var streamingText = ""
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var generationTask: Task<Void, Never>?
    @State private var selectedImageData: Data?
    @State private var photoSelection: PhotosPickerItem?

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

            if let imageData = selectedImageData, let uiImage = UIImage(data: imageData) {
                HStack {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 80)
                        .cornerRadius(8)
                    Button {
                        selectedImageData = nil
                        photoSelection = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
            }

            HStack(spacing: 8) {
                PhotosPicker(selection: $photoSelection, matching: .images) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                }
                .disabled(isGenerating)

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
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedImageData == nil)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .navigationTitle(model.name)
        .onChange(of: photoSelection) { newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                    selectedImageData = data
                }
            }
        }
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
            Text("Messages are processed on-device using \(model.name).")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || selectedImageData != nil else { return }
        guard let client = appState.client else {
            errorMessage = "No client configured. Set device token in Settings."
            return
        }

        inputText = ""
        errorMessage = nil

        if let imageData = selectedImageData {
            let compressed = Self.compressImage(imageData, maxDimension: 1024, quality: 0.8)
            messages.append(.user(text.isEmpty ? "What's in this image?" : text, imageData: compressed))
            selectedImageData = nil
            photoSelection = nil
        } else {
            messages.append(.user(text))
        }

        isGenerating = true
        streamingText = ""

        let chat = OctomilChat(
            modelName: model.name,
            responses: client.responses
        )

        generationTask = Task {
            do {
                let request = ChatRequest(messages: messages)
                for try await chunk in chat.stream(request) {
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

    private static func compressImage(_ data: Data, maxDimension: CGFloat = 1024, quality: CGFloat = 0.8) -> Data {
        guard let image = UIImage(data: data) else { return data }
        let scale = min(1.0, maxDimension / max(image.size.width, image.size.height))
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
        return resized.jpegData(compressionQuality: quality) ?? data
    }
}

// MARK: - Chat Bubble

private struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 48) }

            VStack(alignment: .leading, spacing: 4) {
                if let parts = message.parts {
                    ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                        switch part {
                        case .image(let data, _, _, _):
                            if let data, let decoded = Data(base64Encoded: data),
                               let uiImage = UIImage(data: decoded) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxHeight: 200)
                                    .cornerRadius(8)
                            }
                        case .text(let text):
                            if !text.isEmpty {
                                Text(text)
                                    .textSelection(.enabled)
                            }
                        default:
                            EmptyView()
                        }
                    }
                } else {
                    Text(message.content ?? "")
                        .textSelection(.enabled)
                }
            }
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
