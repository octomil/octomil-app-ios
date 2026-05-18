import AVFoundation
import CoreImage
import Foundation
import UIKit

/// Uploads compressed JPEG thumbnails of camera frames to the Octomil server.
///
/// Pairs with the server-side `frame_thumbnails.py` endpoint:
///   POST /api/v1/device-agent/frame-thumbnails/{device_id}  (multipart)
///
/// The dashboard's `LatestFrameTile` polls the GET counterpart every ~5s
/// and renders a grid. There's no value in uploading faster than the
/// dashboard polls; default interval here matches.
///
/// **Throttling.** `submit(...)` no-ops unless the configured `interval`
/// (default 5 s) has elapsed since the last successful POST. The camera
/// capture queue calls `submit` at ~10-20 fps; the uploader picks one
/// frame per interval.
///
/// **Compression.** Target ~50 KB JPEG. Resize to 320×240 (matches the
/// dashboard cell aspect ratio for free) and encode at quality 0.7.
/// Hard cap at 256 KB to match the server's `_MAX_THUMBNAIL_BYTES`;
/// if a frame exceeds, drop quality and retry once.
///
/// **No payload caching across the queue.** Uploads fire-and-forget;
/// failures log + retry on the next interval. Demo-mode: we don't
/// queue frames during connectivity gaps.
final class ThumbnailUploader: @unchecked Sendable {
    private let serverURL: URL
    private let deviceToken: String
    private let deviceId: String
    private let interval: TimeInterval

    private let session: URLSession
    private let ciContext = CIContext()
    private let lock = NSLock()
    private var lastUploadedAt: Date?

    /// Initialize. `serverURL` should be the base (e.g.
    /// `https://api.octomil.com`) without `/api/v1` — this class
    /// appends the path itself.
    init(
        serverURL: URL,
        deviceToken: String,
        deviceId: String,
        interval: TimeInterval = 5.0,
        session: URLSession = .shared
    ) {
        self.serverURL = serverURL
        self.deviceToken = deviceToken
        self.deviceId = deviceId
        self.interval = interval
        self.session = session
    }

    /// Submit a frame. No-ops if throttled. Safe to call from the
    /// camera capture queue.
    func submit(pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) {
        lock.lock()
        let now = Date()
        if let last = lastUploadedAt, now.timeIntervalSince(last) < interval {
            lock.unlock()
            return
        }
        lastUploadedAt = now
        lock.unlock()

        guard let jpeg = encodeJPEG(pixelBuffer: pixelBuffer, orientation: orientation) else {
            return
        }
        upload(jpeg: jpeg)
    }

    // MARK: - Private

    private func encodeJPEG(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation
    ) -> Data? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(orientation)
        // Scale to 320 wide preserving aspect ratio. The camera preset is
        // hd1280x720; ~4× downsample lands around ~50 KB JPEG @ q=0.7.
        let targetWidth: CGFloat = 320
        let scale = targetWidth / ciImage.extent.width
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let cgImage = ciContext.createCGImage(scaled, from: scaled.extent) else {
            return nil
        }
        let uiImage = UIImage(cgImage: cgImage)

        // Quality 0.7 is a reasonable JPEG default for thumbnails;
        // drop to 0.5 if we somehow exceed the server cap.
        var encoded = uiImage.jpegData(compressionQuality: 0.7)
        if let existing = encoded, existing.count > 256 * 1024 {
            encoded = uiImage.jpegData(compressionQuality: 0.5)
        }
        return encoded
    }

    private func upload(jpeg: Data) {
        let endpoint = serverURL
            .appendingPathComponent("api/v1/device-agent/frame-thumbnails")
            .appendingPathComponent(deviceId)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(deviceToken)", forHTTPHeaderField: "Authorization")

        // Multipart body. The server accepts a single `file` field
        // per FastAPI's UploadFile binding.
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )

        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(
            Data("Content-Disposition: form-data; name=\"file\"; filename=\"frame.jpg\"\r\n".utf8)
        )
        body.append(Data("Content-Type: image/jpeg\r\n\r\n".utf8))
        body.append(jpeg)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        let task = session.uploadTask(with: request, from: body) { _, response, error in
            // Fire-and-forget; log on failure so devs can see what
            // happened during a demo run. Demo scope: no retries,
            // no offline queue.
            if let error {
                print("[ThumbnailUploader] upload failed: \(error.localizedDescription)")
                return
            }
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                print("[ThumbnailUploader] HTTP \(http.statusCode) from server")
            }
        }
        task.resume()
    }
}
