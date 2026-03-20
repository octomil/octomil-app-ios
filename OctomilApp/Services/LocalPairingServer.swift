import Foundation
import Network

/// Lightweight HTTP server for receiving pairing codes from the CLI
/// and exposing debug-only golden-path test endpoints.
///
/// Routes:
/// - `POST /pair` — receive a pairing code from the CLI
/// - `GET /golden/status` — report current app state for test harness
/// - `POST /golden/reset` — clear credentials and cached models
final class LocalPairingServer {
    typealias PairHandler = (_ code: String, _ host: String?, _ modelName: String?) -> Void

    private let handler: PairHandler
    private var listener: NWListener?
    private(set) var port: UInt16 = 0

    /// Returns a JSON-serializable dictionary describing the current app state.
    var statusProvider: (() -> [String: Any])?

    /// Clears credentials, cached models, and resets the app to a fresh state.
    var resetHandler: (() -> Void)?

    init(onPair: @escaping PairHandler) {
        self.handler = onPair
    }

    func start() {
        do {
            let params = NWParameters.tcp
            listener = try NWListener(using: params, on: .any)
        } catch {
            print("[LocalServer] Failed to create listener: \(error)")
            return
        }

        listener?.stateUpdateHandler = { [weak self] state in
            if case .ready = state, let port = self?.listener?.port?.rawValue {
                self?.port = port
                print("[LocalServer] Listening on port \(port)")
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        listener?.start(queue: .global(qos: .userInitiated))
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            defer { connection.cancel() }

            guard let data, error == nil else { return }

            let request = String(data: data, encoding: .utf8) ?? ""

            if request.hasPrefix("POST /pair") {
                self?.handlePair(connection: connection, request: request)
            } else if request.hasPrefix("GET /golden/status") {
                self?.handleGoldenStatus(connection: connection)
            } else if request.hasPrefix("POST /golden/reset") {
                self?.handleGoldenReset(connection: connection)
            } else {
                self?.sendResponse(connection: connection, status: "404 Not Found", body: "Not Found")
            }
        }
    }

    // MARK: - Route Handlers

    private func handlePair(connection: NWConnection, request: String) {
        guard let bodyRange = request.range(of: "\r\n\r\n") ?? request.range(of: "\n\n") else {
            sendResponse(connection: connection, status: "400 Bad Request", body: "No body")
            return
        }

        let bodyString = String(request[bodyRange.upperBound...])
        guard let bodyData = bodyString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
              let code = json["code"] as? String else {
            sendResponse(connection: connection, status: "400 Bad Request", body: "Invalid JSON")
            return
        }

        let host = json["host"] as? String
        let modelName = json["model_name"] as? String

        handler(code, host, modelName)
        sendResponse(connection: connection, status: "200 OK", body: "{\"status\":\"ok\"}")
    }

    private func handleGoldenStatus(connection: NWConnection) {
        let status: [String: Any]
        if let provider = statusProvider {
            status = provider()
        } else {
            status = Self.defaultStatusDict
        }

        if let data = try? JSONSerialization.data(withJSONObject: status),
           let body = String(data: data, encoding: .utf8) {
            sendResponse(connection: connection, status: "200 OK", body: body)
        } else {
            sendResponse(connection: connection, status: "500 Internal Server Error", body: "{\"error\":\"serialization\"}")
        }
    }

    private func handleGoldenReset(connection: NWConnection) {
        if let handler = resetHandler {
            handler()
            sendResponse(connection: connection, status: "200 OK", body: "{\"status\":\"ok\"}")
        } else {
            sendResponse(connection: connection, status: "200 OK", body: "{\"status\":\"noop\"}")
        }
    }

    // MARK: - Helpers

    private func sendResponse(connection: NWConnection, status: String, body: String) {
        let response = "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    static let defaultStatusDict: [String: Any] = [
        "phase": "idle",
        "paired": false,
        "device_registered": false,
        "model_downloaded": false,
        "model_activated": false,
        "active_model": NSNull(),
        "active_version": NSNull(),
        "model_count": 0,
        "last_error": NSNull(),
    ]
}
