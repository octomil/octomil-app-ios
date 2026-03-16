import SwiftUI
import AVFoundation
import Octomil

struct TranscriptionScreen: View {
    @EnvironmentObject private var appState: AppState
    @State private var isRecording = false
    @State private var transcriptionText = ""
    @State private var statusMessage = "Tap the microphone to start recording."
    @State private var errorMessage: String?
    @State private var audioRecorder: AVAudioRecorder?
    @State private var recordingURL: URL?
    @State private var isTranscribing = false

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
        .navigationTitle("Transcription")
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
            Text("Speech-to-Text")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Record audio and transcribe it on-device.")
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

        // Request permission
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
            statusMessage = "Recording... Tap to stop."
        } catch {
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
        }
    }

    private func stopRecording() {
        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false
        statusMessage = "Transcribing..."

        guard let url = recordingURL else {
            errorMessage = "No recording file found."
            return
        }

        transcribe(url: url)
    }

    private func transcribe(url: URL) {
        guard let client = appState.client else {
            errorMessage = "No client configured. Set device token in Settings."
            return
        }

        isTranscribing = true

        Task {
            do {
                let audioData = try Data(contentsOf: url)
                let result = try await client.audio.transcriptions.create(audio: audioData)
                await MainActor.run {
                    transcriptionText = result.text
                    statusMessage = "Tap the microphone to record again."
                    isTranscribing = false
                }
                // Clean up temp file
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
