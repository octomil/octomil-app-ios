#if DEBUG
import Foundation
import Octomil
import OctomilClient

/// Exercises each model capability through the same code paths the app screens use.
/// Debug-only — invoked by `POST /golden/test/*` endpoints on the local pairing server.
final class GoldenTestRunner: @unchecked Sendable {

    private let getModels: () -> [StoredModel]
    private let getClient: () -> OctomilClient?

    init(models: @escaping () -> [StoredModel], client: @escaping () -> OctomilClient?) {
        self.getModels = models
        self.getClient = client
    }

    // MARK: - Run All

    func runAll() async -> [String: Any] {
        let models = getModels()
        var results: [[String: Any]] = []
        var passed = 0, failed = 0, skipped = 0

        // Group models by capability and run each
        let byCapability = Dictionary(grouping: models, by: { $0.capability })

        // Chat
        if let chatModel = byCapability[.chat]?.first {
            let r = await runChat(model: chatModel, prompt: "What is 2+2? Answer in one word.", maxTokens: 32)
            results.append(r)
            if r["skipped"] as? Bool == true { skipped += 1 }
            else if r["passed"] as? Bool == true { passed += 1 }
            else { failed += 1 }
        }

        // Transcription (live)
        if let txModel = byCapability[.transcription]?.first {
            let r = await runTranscribe(model: txModel, fixture: "hello", mode: "live")
            results.append(r)
            if r["skipped"] as? Bool == true { skipped += 1 }
            else if r["passed"] as? Bool == true { passed += 1 }
            else { failed += 1 }
        }

        // Transcription (batch)
        if let txModel = byCapability[.transcription]?.first {
            let r = await runTranscribe(model: txModel, fixture: "hello", mode: "batch")
            results.append(r)
            if r["skipped"] as? Bool == true { skipped += 1 }
            else if r["passed"] as? Bool == true { passed += 1 }
            else { failed += 1 }
        }

        // Prediction
        if let predModel = byCapability[.keyboardPrediction]?.first {
            let r = await runPredict(model: predModel, prefix: "The weather today is", n: 3)
            results.append(r)
            if r["skipped"] as? Bool == true { skipped += 1 }
            else if r["passed"] as? Bool == true { passed += 1 }
            else { failed += 1 }
        }

        let total = passed + failed + skipped
        return [
            "results": results,
            "summary": [
                "total": total,
                "passed": passed,
                "failed": failed,
                "skipped": skipped,
            ]
        ]
    }

    // MARK: - Chat

    func runChat(model: StoredModel, prompt: String, maxTokens: Int) async -> [String: Any] {
        guard let client = getClient() else {
            return result(model: model.name, capability: "chat", skipped: true, error: "no client")
        }

        let start = CFAbsoluteTimeGetCurrent()
        var firstTokenTime: CFAbsoluteTime?
        var text = ""
        var tokenCount = 0

        do {
            let chat = OctomilChat(modelName: model.name, responses: client.responses)
            for try await chunk in chat.stream(prompt) {
                if let content = chunk.choices.first?.delta.content, !content.isEmpty {
                    if firstTokenTime == nil { firstTokenTime = CFAbsoluteTimeGetCurrent() }
                    text += content
                    tokenCount += 1
                }
            }

            let totalMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
            let ttftMs = firstTokenTime.map { ($0 - start) * 1000 }
            let passed = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            return result(
                model: model.name, capability: "chat", passed: passed,
                assertion: "non_empty_text",
                metrics: [
                    "ttft_ms": ttftMs.map { Int($0) } as Any,
                    "total_ms": Int(totalMs),
                    "token_count": tokenCount,
                ],
                output: ["text": text]
            )
        } catch {
            let totalMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
            return result(
                model: model.name, capability: "chat", passed: false,
                error: error.localizedDescription,
                metrics: ["total_ms": Int(totalMs)]
            )
        }
    }

    // MARK: - Transcription

    func runTranscribe(model: StoredModel, fixture: String, mode: String) async -> [String: Any] {
        let capability = "transcription_\(mode)"

        // Load WAV fixture from bundle
        guard let wavURL = Bundle.main.url(forResource: fixture == "hello" ? "hello_16khz" : fixture, withExtension: "wav"),
              let wavData = try? Data(contentsOf: wavURL) else {
            return result(model: model.name, capability: capability, skipped: true, error: "fixture not found: \(fixture)")
        }

        if mode == "live" {
            return await runLiveTranscription(model: model, wavData: wavData, capability: capability)
        } else {
            return await runBatchTranscription(model: model, wavData: wavData, capability: capability)
        }
    }

    private func runLiveTranscription(model: StoredModel, wavData: Data, capability: String) async -> [String: Any] {
        guard let modelURL = model.compiledModelURL else {
            return result(model: model.name, capability: capability, skipped: true, error: "no model path")
        }

        let start = CFAbsoluteTimeGetCurrent()

        guard let transcriber = LiveTranscriberFactory.shared.create(
            engine: model.runtime, modelURL: modelURL
        ) else {
            return result(model: model.name, capability: capability, skipped: true, error: "LiveTranscriberFactory returned nil for engine=\(model.runtime)")
        }

        do {
            try transcriber.start()
        } catch {
            return result(model: model.name, capability: capability, passed: false, error: "start failed: \(error.localizedDescription)")
        }

        // Convert WAV data to Float samples (skip 44-byte WAV header, 16-bit PCM)
        let samples = wavToFloatSamples(wavData)

        // Feed in chunks (simulating real-time audio at 16kHz, 480-sample chunks = 30ms)
        let chunkSize = 480
        for i in stride(from: 0, to: samples.count, by: chunkSize) {
            let end = min(i + chunkSize, samples.count)
            let chunk = Array(samples[i..<end])
            transcriber.feedSamples(chunk)
            // Small delay to let the recognizer process
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }

        // Get final result
        let finalText = transcriber.stop()
        let totalMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
        let passed = !finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return result(
            model: model.name, capability: capability, passed: passed,
            assertion: "non_empty_text",
            metrics: ["total_ms": Int(totalMs)],
            output: ["text": finalText]
        )
    }

    private func runBatchTranscription(model: StoredModel, wavData: Data, capability: String) async -> [String: Any] {
        let start = CFAbsoluteTimeGetCurrent()

        // Try local runtime first
        if let runtime = ModelRuntimeRegistry.shared.resolve(modelId: model.name) {
            do {
                let msg = RuntimeMessage(role: .user, parts: [.audio(data: wavData, mediaType: "audio/wav")])
                let request = RuntimeRequest(messages: [msg])
                let response = try await runtime.run(request: request)
                let cleanText = response.text
                    .replacingOccurrences(of: "\0", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let totalMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
                let passed = !cleanText.isEmpty

                return result(
                    model: model.name, capability: capability, passed: passed,
                    assertion: "non_empty_text",
                    metrics: ["total_ms": Int(totalMs)],
                    output: ["text": cleanText]
                )
            } catch {
                let totalMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
                return result(
                    model: model.name, capability: capability, passed: false,
                    error: error.localizedDescription,
                    metrics: ["total_ms": Int(totalMs)]
                )
            }
        }

        // Fall back to cloud API
        if let client = getClient() {
            do {
                let txResult = try await client.audio.transcriptions.create(audio: wavData, model: model.name)
                let totalMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
                let passed = !txResult.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

                return result(
                    model: model.name, capability: capability, passed: passed,
                    assertion: "non_empty_text",
                    metrics: ["total_ms": Int(totalMs)],
                    output: ["text": txResult.text]
                )
            } catch {
                let totalMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
                return result(
                    model: model.name, capability: capability, passed: false,
                    error: error.localizedDescription,
                    metrics: ["total_ms": Int(totalMs)]
                )
            }
        }

        return result(model: model.name, capability: capability, skipped: true, error: "no runtime or client available")
    }

    // MARK: - Prediction

    func runPredict(model: StoredModel, prefix: String, n: Int) async -> [String: Any] {
        guard let client = getClient() else {
            return result(model: model.name, capability: "prediction", skipped: true, error: "no client")
        }

        let start = CFAbsoluteTimeGetCurrent()

        do {
            let predResult = try await client.text.predictions.create(input: prefix, n: n)
            let totalMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
            let texts = predResult.predictions.map(\.text)
            let passed = !texts.isEmpty && texts.contains(where: { !$0.isEmpty })

            return result(
                model: model.name, capability: "prediction", passed: passed,
                assertion: "non_empty_predictions",
                metrics: [
                    "total_ms": Int(totalMs),
                    "prediction_count": texts.count,
                ],
                output: ["predictions": texts]
            )
        } catch {
            let totalMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
            return result(
                model: model.name, capability: "prediction", passed: false,
                error: error.localizedDescription,
                metrics: ["total_ms": Int(totalMs)]
            )
        }
    }

    // MARK: - Helpers

    private func result(
        model: String,
        capability: String,
        passed: Bool = false,
        skipped: Bool = false,
        error: String? = nil,
        assertion: String? = nil,
        metrics: [String: Any] = [:],
        output: [String: Any] = [:]
    ) -> [String: Any] {
        var r: [String: Any] = [
            "model": model,
            "capability": capability,
            "passed": passed,
            "skipped": skipped,
            "error": error as Any? ?? NSNull(),
            "assertion": assertion as Any? ?? NSNull(),
            "metrics": metrics,
            "output": output,
        ]
        return r
    }

    /// Convert 16-bit PCM WAV data to normalized Float samples.
    private func wavToFloatSamples(_ data: Data) -> [Float] {
        // Skip 44-byte WAV header
        guard data.count > 44 else { return [] }
        let pcmData = data.subdata(in: 44..<data.count)
        let sampleCount = pcmData.count / 2

        var samples = [Float](repeating: 0, count: sampleCount)
        pcmData.withUnsafeBytes { raw in
            let int16Ptr = raw.bindMemory(to: Int16.self)
            for i in 0..<sampleCount {
                samples[i] = Float(int16Ptr[i]) / 32768.0
            }
        }
        return samples
    }
}
#endif
