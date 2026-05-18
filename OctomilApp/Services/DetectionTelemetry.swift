import Foundation
import Octomil

/// Per-inference telemetry reporter for vision detection.
///
/// Each call to `report(...)` emits an `inference.started` + `inference.completed`
/// pair through `client.telemetry.track(...)`, which the SDK batches through
/// the v2 OTLP pipeline. Server's `telemetry_events_v2._handle_inference_event`
/// (octomil-server/server/app/routers/telemetry_events_v2.py) translates the
/// `inference.*` event names into `InferenceSession` rows that drive
/// `MonitoringService.get_version_inference_health()` — the same signal
/// the canary auto-pause flow reads (Tier 1 health gate).
///
/// **Throttling.** Camera capture produces ~10-20 frames/sec; reporting every
/// frame would flood the queue. `report(...)` no-ops unless the configured
/// `interval` has elapsed since the last reported frame. The default 1 Hz
/// gives 60 sessions/min — plenty of resolution for the auto-pause flow's
/// 10-min rolling window (default health gate fires at 5% error rate over
/// ≥2 ticks ≈ 2 min, so even sparse vision data has signal).
///
/// **Failure semantics.** The auto-pause flow distinguishes `completed` vs
/// `failed` status. For vision, we DO NOT synthetically classify low-quality
/// detections as `failed` — that would conflate "model running" with "model
/// good." Vision-quality drift is a separate signal that doesn't belong in
/// the infra-error gate. The iPad always reports `completed`; demo-time
/// regression is injected via the server-side `inject_regression.py`
/// script (canary cohort) which writes synthetic failed sessions for the
/// auto-pause trigger.
final class DetectionTelemetry: @unchecked Sendable {
    private let client: OctomilClient
    private let modelId: String
    private let modelVersion: String
    private let interval: TimeInterval
    private let lock = NSLock()
    private var lastReported: Date?

    init(
        client: OctomilClient,
        modelId: String,
        modelVersion: String,
        interval: TimeInterval = 1.0
    ) {
        self.client = client
        self.modelId = modelId
        self.modelVersion = modelVersion
        self.interval = interval
    }

    /// Report a single inference frame. Throttled to `interval` seconds.
    ///
    /// Safe to call from any thread (`CameraSession.onFrame` is the typical
    /// caller, which runs on the camera capture queue, not MainActor).
    func report(latencyMs: Double, detectionCount: Int) {
        lock.lock()
        let now = Date()
        if let last = lastReported, now.timeIntervalSince(last) < interval {
            lock.unlock()
            return
        }
        lastReported = now
        lock.unlock()

        let sessionId = UUID().uuidString
        let baseAttrs: [String: Any] = [
            "inference.session_id": sessionId,
            "model.id": modelId,
            "model.version": modelVersion,
            "inference.modality": "image"
        ]

        client.telemetry.track(name: "inference.started", attributes: baseAttrs)

        var completedAttrs = baseAttrs
        completedAttrs["inference.ttfc_ms"] = Int(latencyMs.rounded())
        completedAttrs["inference.total_duration_ms"] = Int(latencyMs.rounded())
        // Vision-specific extension; server may ignore unknown attrs but
        // they ride through the OTLP envelope for ad-hoc dashboard use.
        completedAttrs["inference.detection_count"] = detectionCount

        client.telemetry.track(name: "inference.completed", attributes: completedAttrs)
    }
}
