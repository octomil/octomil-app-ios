import SwiftUI
import AVFoundation
import Octomil

/// On-device object detection using the device camera.
///
/// Mirrors `TranscriptionScreen` for the vision modality. Renders the
/// live camera preview with bounding-box overlays.
///
/// **Current implementation uses raw `MLModel(contentsOf:)` + `VNCoreMLRequest`
/// directly — it bypasses the Octomil SDK.** This is a temporary shortcut so
/// `DetectionScreen` is testable without the full pair flow being green
/// (blocked by the AppState `recoverModels` API drift).
///
/// **Followup (production path):** load via `client.downloadModel(modelId:, version:)`,
/// returns `OctomilModel`, call `await model.warmup()`, then pass
/// `model.mlModel` to `VNCoreMLModel(for:)`. That wires lifecycle + telemetry
/// + canary participation through the SDK; the Apple Vision framework still
/// runs the per-frame inference.
///
/// V1 demo scope:
///   - Model resolved from (1) `model.compiledModelURL` if paired,
///     (2) bundled `YOLOv3Tiny.mlmodelc` as dev fallback. **Both paths
///     currently bypass the SDK wrapper.**
///   - No telemetry yet — needs `OctomilModel` wrapper or direct sink call.
///   - No cohort/canary integration — needs the production load path above.
struct DetectionScreen: View {
    @EnvironmentObject private var appState: AppState
    let model: StoredModel

    @State private var detector: ObjectDetector?
    @State private var detections: [Detection] = []
    @State private var isRunning = false
    @State private var statusMessage = "Press Start to begin."
    @State private var errorMessage: String?
    @State private var lastInferenceMs: Double = 0
    @State private var camera = CameraSession()

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black

                if isRunning {
                    CameraPreviewView(session: camera.session)
                        .overlay(
                            DetectionOverlay(detections: detections)
                                .allowsHitTesting(false)
                        )
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "viewfinder")
                            .font(.system(size: 64))
                            .foregroundStyle(.white.opacity(0.3))
                        Text("Camera idle")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            statusBar

            controls
        }
        .navigationTitle(model.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadDetectorIfNeeded() }
        .onDisappear { camera.stop() }
    }

    // MARK: - Subviews

    private var statusBar: some View {
        VStack(spacing: 4) {
            HStack {
                Circle()
                    .fill(isRunning ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if isRunning && lastInferenceMs > 0 {
                    Text("\(Int(lastInferenceMs))ms")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if let error = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }

    private var controls: some View {
        HStack(spacing: 16) {
            Button(role: isRunning ? .destructive : nil) {
                if isRunning { stopCapture() } else { startCapture() }
            } label: {
                Label(isRunning ? "Stop" : "Start",
                      systemImage: isRunning ? "stop.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            // No detector → can't run inference. Holds for both the
            // pre-load state ('Press Start to begin.') and the
            // failed-load state (errorMessage set, no detector).
            .disabled(detector == nil)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .background(Color(.systemBackground))
    }

    // MARK: - Actions

    private func loadDetectorIfNeeded() {
        guard detector == nil else { return }

        // Followup: replace with `client.downloadModel(modelId:, version:)` →
        // `OctomilModel.warmup()` → `OctomilModel.mlModel`. Current code
        // bypasses the SDK wrapper (no warmup, no telemetry, no canary
        // participation). Blocked on AppState reconciler-API migration.
        //
        // Resolution order (both paths currently raw MLModel — see followup above):
        //   1. Octomil-paired model URL (closest to the production path).
        //   2. Bundled YOLOv3Tiny.mlmodelc — DEV ONLY; populated by
        //      scripts/fetch_dev_model.sh; gitignored. Not in production builds.
        let url: URL
        let source: String
        if let pairedURL = model.compiledModelURL {
            url = pairedURL
            source = "paired (raw MLModel — SDK wrapper TODO)"
        } else if let bundled = Bundle.main.url(forResource: "YOLOv3Tiny", withExtension: "mlmodelc") {
            url = bundled
            source = "DEV FALLBACK (YOLOv3Tiny, no SDK)"
        } else {
            errorMessage = "No model available. Pair a vision model or run scripts/fetch_dev_model.sh."
            return
        }

        do {
            detector = try ObjectDetector(modelURL: url)
            statusMessage = "Loaded \(source). Ready."
        } catch {
            errorMessage = "Failed to load model: \(error.localizedDescription)"
        }
    }

    private func startCapture() {
        Task {
            let status = await CameraSession.requestAccess()
            guard status == .authorized else {
                errorMessage = "Camera access denied. Enable in Settings."
                return
            }
            do {
                try camera.configure()
            } catch {
                errorMessage = "Camera unavailable: \(error.localizedDescription)"
                return
            }

            camera.onFrame = { [detector] pixelBuffer, orientation in
                guard let detector else { return }
                let results = detector.detect(pixelBuffer: pixelBuffer, orientation: orientation)
                Task { @MainActor in
                    self.detections = results
                    self.lastInferenceMs = detector.lastInferenceMs
                }
            }

            camera.start()
            isRunning = true
            statusMessage = "Running"
            errorMessage = nil
        }
    }

    private func stopCapture() {
        camera.stop()
        camera.onFrame = nil
        isRunning = false
        detections = []
        statusMessage = "Stopped"
    }
}

// MARK: - Camera preview (UIViewRepresentable)

private struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        applyPortraitOrientation(to: view.previewLayer.connection)
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        uiView.previewLayer.session = session
        applyPortraitOrientation(to: uiView.previewLayer.connection)
    }

    /// Orient the preview layer's connection to portrait. This is independent
    /// of the data-output connection in `CameraSession` (which deliberately
    /// stays unrotated so Vision can interpret sensor-native buffers via
    /// orientation hint).
    private func applyPortraitOrientation(to connection: AVCaptureConnection?) {
        guard let connection else { return }
        if #available(iOS 17.0, macOS 14.0, *) {
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        } else {
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
        }
    }

    final class PreviewUIView: UIView {
        // swiftlint:disable:next static_over_final_class
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        // `layerClass` guarantees the underlying type — force unwrap is the
        // documented CoreAnimation pattern for this idiom.
        // swiftlint:disable:next force_cast
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

// MARK: - Bounding-box overlay

private struct DetectionOverlay: View {
    let detections: [Detection]

    var body: some View {
        GeometryReader { geo in
            ForEach(detections) { detection in
                let rect = boundingRect(for: detection.bbox, in: geo.size)
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .stroke(Color.green, lineWidth: 2)
                        .frame(width: rect.width, height: rect.height)
                    Text("\(detection.label) \(Int(detection.confidence * 100))%")
                        .font(.caption2.monospacedDigit())
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.85))
                        .foregroundStyle(.black)
                        .offset(y: -16)
                }
                .position(x: rect.midX, y: rect.midY)
            }
        }
    }

    /// Vision's coords: origin bottom-left, normalized [0,1].
    /// SwiftUI's coords: origin top-left, points.
    private func boundingRect(for bbox: CGRect, in size: CGSize) -> CGRect {
        CGRect(
            x: bbox.minX * size.width,
            y: (1 - bbox.maxY) * size.height,
            width: bbox.width * size.width,
            height: bbox.height * size.height
        )
    }
}
