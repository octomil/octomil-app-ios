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
    @State private var audioRecorder: AVAudioRecorder?
    @State private var recordingURL: URL?
    @State private var isTranscribing = false

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
            if isRecording {
                audioRecorder?.stop()
                isRecording = false
            }
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
                    beginRecording()
                } else {
                    errorMessage = "Microphone permission denied."
                }
            }
        }
    }

    private func beginRecording() {
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
            statusMessage = isStreaming
                ? "Listening... Tap to stop."
                : "Recording... Tap to stop."
        } catch {
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
        }
    }

    private func stopRecording() {
        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false

        guard let url = recordingURL else {
            errorMessage = "No recording file found."
            return
        }

        statusMessage = "Transcribing..."
        transcribe(url: url)
    }

    private func transcribe(url: URL) {
        isTranscribing = true

        Task {
            do {
                let audioData = try Data(contentsOf: url)

                // Try the API client first, fall back to local runtime registry
                // (paired on-device models don't need a client/device token).
                if let client = appState.client {
                    let result = try await client.audio.transcriptions.create(audio: audioData, model: model.name)
                    await MainActor.run {
                        transcriptionText = result.text
                    }
                } else if let runtime = ModelRuntimeRegistry.shared.resolve(modelId: model.name) {
                    let request = RuntimeRequest(prompt: "", mediaData: audioData, mediaType: "audio")
                    let response = try await runtime.run(request: request)
                    await MainActor.run {
                        transcriptionText = response.text
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
}
