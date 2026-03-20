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
        startListener()
    }

    /// Start and wait until the listener port is assigned (up to 2 s).
    func startAsync() async {
        startListener()
        // Wait for the port to be assigned by the NWListener state handler
        for _ in 0..<20 {
            if port > 0 { return }
            try? await Task.sleep(nanoseconds: 100_000_000) // 100 ms
        }
    }

    private func startListener() {
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

    /// Max body size accepted (2 MB). Prevents abuse on debug endpoints.
    private static let maxBodySize = 2 * 1024 * 1024

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        let deadline = DispatchTime.now() + .seconds(5)
        receiveFullRequest(connection: connection, accumulated: Data(), deadline: deadline) { [weak self] result in
            switch result {
            case .failure:
                connection.cancel()
            case .success(let requestData):
                let request = String(data: requestData, encoding: .utf8) ?? ""
                self?.dispatch(connection: connection, request: request, rawData: requestData)
            }
        }
    }

    /// Read the full HTTP request: headers + body (based on Content-Length).
    /// Loops `connection.receive()` until the complete body is accumulated or deadline.
    private func receiveFullRequest(
        connection: NWConnection,
        accumulated: Data,
        deadline: DispatchTime,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { completion(.failure(NSError(domain: "LocalServer", code: -1))); return }

            if let error {
                completion(.failure(error))
                return
            }
            guard let data else {
                completion(.failure(NSError(domain: "LocalServer", code: -2)))
                return
            }

            var buffer = accumulated
            buffer.append(data)

            // Check size limit
            if buffer.count > Self.maxBodySize {
                self.sendResponse(connection: connection, status: "413 Payload Too Large", body: "{\"error\":\"body too large\"}")
                return
            }

            // Try to find header/body boundary
            let bufferStr = String(data: buffer, encoding: .utf8) ?? ""
            let headerEnd: String.Index?
            let separator: String
            if let range = bufferStr.range(of: "\r\n\r\n") {
                headerEnd = range.upperBound
                separator = "\r\n\r\n"
            } else if let range = bufferStr.range(of: "\n\n") {
                headerEnd = range.upperBound
                separator = "\n\n"
            } else {
                headerEnd = nil
                separator = ""
            }

            guard let bodyStart = headerEnd else {
                // Haven't received full headers yet — keep reading
                if DispatchTime.now() < deadline {
                    self.receiveFullRequest(connection: connection, accumulated: buffer, deadline: deadline, completion: completion)
                } else {
                    completion(.failure(NSError(domain: "LocalServer", code: -3, userInfo: [NSLocalizedDescriptionKey: "timeout waiting for headers"])))
                }
                return
            }

            // Parse Content-Length from headers
            let headersStr = String(bufferStr[..<bufferStr.range(of: separator)!.lowerBound])
            let contentLength = Self.parseContentLength(from: headersStr)

            // Calculate how much body we have
            let bodyStartOffset = bufferStr.distance(from: bufferStr.startIndex, to: bodyStart)
            let bodyReceived = buffer.count - bodyStartOffset

            if bodyReceived >= contentLength {
                // Full request received
                completion(.success(buffer))
            } else if isComplete {
                // Connection closed before full body — use what we have
                completion(.success(buffer))
            } else if DispatchTime.now() < deadline {
                // Need more data
                self.receiveFullRequest(connection: connection, accumulated: buffer, deadline: deadline, completion: completion)
            } else {
                completion(.failure(NSError(domain: "LocalServer", code: -4, userInfo: [NSLocalizedDescriptionKey: "timeout waiting for body"])))
            }
        }
    }

    private static func parseContentLength(from headers: String) -> Int {
        for line in headers.components(separatedBy: .newlines) {
            let lower = line.lowercased()
            if lower.hasPrefix("content-length:") {
                let value = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                return Int(value) ?? 0
            }
        }
        return 0
    }

    private func dispatch(connection: NWConnection, request: String, rawData: Data) {
        if request.hasPrefix("POST /pair") {
            handlePair(connection: connection, request: request)
        } else if request.hasPrefix("GET /golden/status") {
            handleGoldenStatus(connection: connection)
        } else if request.hasPrefix("POST /golden/reset") {
            handleGoldenReset(connection: connection)
        } else {
            sendResponse(connection: connection, status: "404 Not Found", body: "Not Found")
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
