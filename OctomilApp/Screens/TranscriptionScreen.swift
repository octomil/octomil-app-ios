import SwiftUI
import AVFoundation
import Octomil

struct TranscriptionScreen: View {
    @EnvironmentObject private var appState: AppState
    let model: StoredModel

    @State private var isRecording = false
    @State private var transcriptionText = ""
    @State private var statusMessage = ""
    @State private var errorMessage: String?
    @State private var isTranscribing = false

    // Batch recording (whisper)
    @State private var audioRecorder: AVAudioRecorder?
    @State private var recordingURL: URL?

    // Live transcription (sherpa)
    @State private var liveTranscriber: LiveTranscriber?
    @State private var audioEngine: AVAudioEngine?
    @State private var pollingTimer: Timer?

    private var isStreaming: Bool { model.supportsStreaming }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if transcriptionText.isEmpty && !isRecording && !isTranscribing {
                        emptyState
                    }

                    if !transcriptionText.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Transcription")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(transcriptionText)
                                .font(.body)
                                .textSelection(.enabled)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.systemGray6))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .padding(.horizontal, 16)
                    }

                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 16)
                    }
                }
                .padding(.vertical, 16)
            }

            Divider()

            VStack(spacing: 8) {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    if isRecording {
                        stopRecording()
                    } else {
                        startRecording()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(isRecording ? Color.red : Color.blue)
                            .frame(width: 64, height: 64)

                        if isTranscribing {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                                .font(.title2)
                                .foregroundStyle(.white)
                        }
                    }
                }
                .disabled(isTranscribing)
            }
            .padding(.vertical, 16)
        }
        .navigationTitle(model.name)
        .onAppear {
            statusMessage = isStreaming
                ? "Tap the microphone for live transcription."
                : "Tap the microphone to start recording."
        }
        .onDisappear {
            tearDownLiveTranscription()
            audioRecorder?.stop()
            isRecording = false
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(isStreaming ? "Live Transcription" : "Speech-to-Text")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(isStreaming
                 ? "Tap record for live partial transcripts."
                 : "Record audio and transcribe it on-device.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Recording

    private func startRecording() {
        errorMessage = nil

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default)
            try session.setActive(true)
        } catch {
            errorMessage = "Failed to configure audio session: \(error.localizedDescription)"
            return
        }

        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                if granted {
                    if isStreaming {
                        beginLiveRecording()
                    } else {
                        beginBatchRecording()
                    }
                } else {
                    errorMessage = "Microphone permission denied."
                }
            }
        }
    }

    private func stopRecording() {
        if isStreaming {
            stopLiveRecording()
        } else {
            stopBatchRecording()
        }
    }

    // MARK: - Live Transcription (Sherpa)

    private func beginLiveRecording() {
        guard let modelPath = model.modelPath else {
            errorMessage = "No model path available."
            return
        }

        // Validate model directory
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if !fm.fileExists(atPath: modelPath, isDirectory: &isDir) || !isDir.boolValue {
            errorMessage = "Model directory missing. Please re-pair the model."
            return
        }

        let modelURL = URL(fileURLWithPath: modelPath)
        let runtime = model.runtime.lowercased()

        guard let transcriber = LiveTranscriberFactory.shared.create(
            engine: runtime, modelURL: modelURL
        ) else {
            // Fall back to batch if no live transcriber registered
            beginBatchRecording()
            return
        }

        do {
            try transcriber.start()
        } catch {
            errorMessage = "Failed to start transcriber: \(error.localizedDescription)"
            return
        }

        liveTranscriber = transcriber
        transcriptionText = ""

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let hwFormat = inputNode.outputFormat(forBus: 0)

        // Target format: 16kHz mono Float32 for sherpa
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ) else {
            errorMessage = "Could not create target audio format."
            return
        }

        let converter = AVAudioConverter(from: hwFormat, to: targetFormat)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { buffer, _ in
            guard let converter else { return }

            // Calculate output frame count for 16kHz
            let ratio = 16000.0 / hwFormat.sampleRate
            let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
            guard let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: outputFrameCount
            ) else { return }

            var error: NSError?
            converter.convert(to: outputBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            if error == nil, let channelData = outputBuffer.floatChannelData {
                let count = Int(outputBuffer.frameLength)
                let samples = Array(UnsafeBufferPointer(start: channelData[0], count: count))
                transcriber.feedSamples(samples)
            }
        }

        do {
            try engine.start()
        } catch {
            errorMessage = "Failed to start audio engine: \(error.localizedDescription)"
            return
        }

        audioEngine = engine
        isRecording = true
        statusMessage = "Listening..."

        // Poll for partial results every 200ms
        let timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            let partial = transcriber.getPartialResult()
            DispatchQueue.main.async {
                let formatted = Self.formatTranscription(partial)
                if !formatted.isEmpty {
                    self.transcriptionText = formatted
                }
            }
        }
        pollingTimer = timer
    }

    private func stopLiveRecording() {
        pollingTimer?.invalidate()
        pollingTimer = nil

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        let finalText = liveTranscriber?.stop() ?? ""
        liveTranscriber = nil

        let formatted = Self.formatTranscription(finalText)
        transcriptionText = formatted.isEmpty ? "(No speech detected)" : formatted
        isRecording = false
        statusMessage = "Tap the microphone to record again."
    }

    private func tearDownLiveTranscription() {
        pollingTimer?.invalidate()
        pollingTimer = nil
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        _ = liveTranscriber?.stop()
        liveTranscriber = nil
    }

    // MARK: - Batch Recording (Whisper)

    private func beginBatchRecording() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        recordingURL = tempURL

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]

        do {
            let recorder = try AVAudioRecorder(url: tempURL, settings: settings)
            recorder.record()
            audioRecorder = recorder
            isRecording = true
            statusMessage = "Recording... Tap to stop."
        } catch {
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
        }
    }

    private func stopBatchRecording() {
        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false

        guard let url = recordingURL else {
            errorMessage = "No recording file found."
            return
        }

        statusMessage = "Transcribing..."
        transcribeBatch(url: url)
    }

    private func transcribeBatch(url: URL) {
        isTranscribing = true

        Task {
            do {
                if let modelPath = model.modelPath {
                    let fm = FileManager.default
                    var isDir: ObjCBool = false
                    if !fm.fileExists(atPath: modelPath, isDirectory: &isDir) || !isDir.boolValue {
                        throw NSError(domain: "Octomil", code: 0,
                                      userInfo: [NSLocalizedDescriptionKey: "Model directory missing. Please re-pair the model."])
                    }
                }

                let audioData = try Data(contentsOf: url)

                if let runtime = ModelRuntimeRegistry.shared.resolve(modelId: model.name) {
                    let message = RuntimeMessage(role: .user, parts: [.audio(data: audioData, mediaType: "audio/wav")])
                    let request = RuntimeRequest(messages: [message])
                    let response = try await runtime.run(request: request)
                    let cleanText = response.text
                        .replacingOccurrences(of: "\0", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    await MainActor.run {
                        transcriptionText = cleanText.isEmpty ? "(No speech detected)" : cleanText
                    }
                } else if let client = appState.client {
                    let result = try await client.audio.transcriptions.create(audio: audioData, model: model.name)
                    await MainActor.run {
                        transcriptionText = result.text
                    }
                } else {
                    throw NSError(domain: "Octomil", code: 0,
                                  userInfo: [NSLocalizedDescriptionKey: "No runtime found for '\(model.name)'."])
                }

                await MainActor.run {
                    statusMessage = "Tap the microphone to record again."
                    isTranscribing = false
                }
                try? FileManager.default.removeItem(at: url)
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    statusMessage = "Tap the microphone to try again."
                    isTranscribing = false
                }
            }
        }
    }

    // MARK: - Grammar Formatting

    /// Applies basic grammar formatting: capitalize sentences, add punctuation.
    static func formatTranscription(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        // Normalize whitespace
        let words = trimmed.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return "" }

        var result = ""
        var capitalizeNext = true

        for word in words {
            if !result.isEmpty {
                result += " "
            }

            if capitalizeNext {
                result += word.prefix(1).uppercased() + word.dropFirst()
                capitalizeNext = false
            } else {
                result += word
            }

            // Check if word ends a sentence
            if let last = word.last, last == "." || last == "!" || last == "?" {
                capitalizeNext = true
            }
        }

        // Add period at end if missing punctuation
        if let last = result.last, !last.isPunctuation {
            result += "."
        }

        return result
    }
}
