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
/// Three construction paths, in preference order:
///   1. `init(mlModel:)` — accept a pre-loaded `MLModel`. This is the
///      production path: caller hands us `OctomilModel.mlModel` after
///      `client.models.load(...)` + `OctomilModel.warmup()`. SDK owns the
///      lifecycle (download, cache, warmup, telemetry, canary participation).
///   2. `init(modelURL:)` — load `MLModel(contentsOf:)` directly. Used by
///      the dev fallback that reads a bundled `.mlmodelc` resource. Bypasses
///      the SDK wrapper; no warmup, no telemetry.
///
/// Vision-side behaviour is identical across paths — `VNCoreMLModel` +
/// `VNCoreMLRequest` over the same underlying `MLModel`. Only the
/// lifecycle owner differs.
final class ObjectDetector {
    private let request: VNCoreMLRequest
    private(set) var lastInferenceMs: Double = 0

    /// Production path — caller obtained the `MLModel` via the SDK.
    init(mlModel: MLModel) throws {
        let visionModel = try VNCoreMLModel(for: mlModel)
        self.request = VNCoreMLRequest(model: visionModel)
        self.request.imageCropAndScaleOption = .scaleFill
    }

    /// Dev fallback — load directly from a compiled `.mlmodelc` on disk.
    /// Bypasses the SDK; no warmup, no telemetry.
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
