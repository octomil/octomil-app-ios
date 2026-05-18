import CoreML
import CoreVideo
import Foundation
import Vision

/// One detected object — coordinates are normalized [0,1] in Vision's
/// origin-bottom-left coordinate space.
struct Detection: Identifiable {
    let id = UUID()
    let label: String
    let confidence: Float
    let bbox: CGRect
}

/// Loads a CoreML model and runs `VNCoreMLRequest` per frame.
///
/// Two model paths are supported:
///   1. URL — point at an `.mlmodelc` (compiled) on disk. This is what the
///      Octomil SDK's `ModelManager.downloadModel(...)` returns.
///   2. Bundled resource — used during development only. Set the bundle
///      resource name via `init(bundledResource:)`.
///
/// In v1 demos we use a YOLOv8n-style detector with `VNRecognizedObjectObservation`
/// outputs (Vision auto-decodes Ultralytics-shape outputs when the model is
/// converted with `coremltools` and exported with NMS layers attached).
final class ObjectDetector {
    private let request: VNCoreMLRequest
    private(set) var lastInferenceMs: Double = 0

    init(modelURL: URL) throws {
        let model = try MLModel(contentsOf: modelURL)
        let visionModel = try VNCoreMLModel(for: model)
        self.request = VNCoreMLRequest(model: visionModel)
        self.request.imageCropAndScaleOption = .scaleFill
    }

    /// Run detection on one frame. Returns top-N by confidence (default 20).
    /// Caller controls back-pressure by deciding how often to call this.
    func detect(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        topN: Int = 20
    ) -> [Detection] {
        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: orientation,
            options: [:]
        )

        let start = CFAbsoluteTimeGetCurrent()
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        lastInferenceMs = (CFAbsoluteTimeGetCurrent() - start) * 1000

        guard let observations = request.results as? [VNRecognizedObjectObservation] else {
            return []
        }

        return observations
            .sorted { $0.confidence > $1.confidence }
            .prefix(topN)
            .compactMap { obs -> Detection? in
                guard let top = obs.labels.first else { return nil }
                return Detection(
                    label: top.identifier,
                    confidence: top.confidence,
                    bbox: obs.boundingBox
                )
            }
    }
}
