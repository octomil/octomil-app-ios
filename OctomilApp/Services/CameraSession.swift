import AVFoundation
import CoreVideo
import Foundation

/// Wraps `AVCaptureSession` for back-camera video frames.
///
/// Mirrors the role `AVAudioEngine` plays for the live transcription path:
/// owns capture lifecycle and forwards frames to a single delegate that runs
/// inference. UI state stays in the SwiftUI screen; this stays headless.
final class CameraSession: NSObject {
    /// Per-frame callback. Runs on `frameQueue` — bounce to MainActor before
    /// touching `@Published` state.
    var onFrame: ((CVPixelBuffer, CGImagePropertyOrientation) -> Void)?

    let session = AVCaptureSession()
    private let frameQueue = DispatchQueue(label: "ai.octomil.camera.frames", qos: .userInitiated)
    private let videoOutput = AVCaptureVideoDataOutput()
    private var configured = false

    /// Camera authorization. Caller must handle `.notDetermined` by requesting.
    static var authorizationStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    /// Request access if needed. Returns the resolved status.
    static func requestAccess() async -> AVAuthorizationStatus {
        if authorizationStatus == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
        }
        return authorizationStatus
    }

    /// Configure inputs/outputs once. Throws if no camera is available.
    func configure() throws {
        guard !configured else { return }

        session.beginConfiguration()
        session.sessionPreset = .hd1280x720

        // Back camera input.
        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            session.commitConfiguration()
            throw CameraError.deviceUnavailable
        }
        session.addInput(input)

        // Frame output — BGRA so Vision can hand it to CoreML directly.
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: frameQueue)

        guard session.canAddOutput(videoOutput) else {
            session.commitConfiguration()
            throw CameraError.outputUnavailable
        }
        session.addOutput(videoOutput)

        // NOTE: deliberately NOT setting `videoRotationAngle` /
        // `videoOrientation` on the data-output connection. Doing so would
        // physically rotate the pixel buffer delivered to the delegate, and
        // we'd be double-rotating because we also tell Vision the source
        // orientation (`.right` for a portrait back-camera capture). Vision
        // can interpret the sensor-native buffer directly via the orientation
        // hint — cheaper and avoids the off-by-90 detection bug.
        //
        // The preview layer rotation is handled separately in the SwiftUI
        // CameraPreviewView (different AVCaptureConnection).

        session.commitConfiguration()
        configured = true
    }

    /// Start capture on a background queue. Safe to call repeatedly.
    func start() {
        frameQueue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    /// Stop capture. Releases the camera so other apps can use it.
    func stop() {
        frameQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    enum CameraError: Error {
        case deviceUnavailable
        case outputUnavailable
    }
}

extension CameraSession: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame?(pixelBuffer, .right) // Back-camera + portrait lock = .right.
    }
}
