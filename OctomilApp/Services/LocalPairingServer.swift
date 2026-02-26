import Foundation
import Network

/// Lightweight HTTP server for receiving pairing codes from the CLI.
///
/// Listens on a random port and accepts POST /pair requests with JSON body:
/// ```json
/// {"code": "ABC123", "host": "https://api.octomil.com/api/v1", "model_name": "phi-4-mini"}
/// ```
final class LocalPairingServer {
    typealias PairHandler = (_ code: String, _ host: String?, _ modelName: String?) -> Void

    private let handler: PairHandler
    private var listener: NWListener?
    private(set) var port: UInt16 = 0

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

            // Only handle POST /pair
            guard request.hasPrefix("POST /pair") else {
                self?.sendResponse(connection: connection, status: "404 Not Found", body: "Not Found")
                return
            }

            // Extract JSON body (after double newline)
            guard let bodyRange = request.range(of: "\r\n\r\n") ?? request.range(of: "\n\n") else {
                self?.sendResponse(connection: connection, status: "400 Bad Request", body: "No body")
                return
            }

            let bodyString = String(request[bodyRange.upperBound...])
            guard let bodyData = bodyString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
                  let code = json["code"] as? String else {
                self?.sendResponse(connection: connection, status: "400 Bad Request", body: "Invalid JSON")
                return
            }

            let host = json["host"] as? String
            let modelName = json["model_name"] as? String

            self?.handler(code, host, modelName)
            self?.sendResponse(connection: connection, status: "200 OK", body: "{\"status\":\"ok\"}")
        }
    }

    private func sendResponse(connection: NWConnection, status: String, body: String) {
        let response = "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
