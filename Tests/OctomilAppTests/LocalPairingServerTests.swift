import Testing
import Foundation
@testable import OctomilAppLib
import Network

@Suite("LocalPairingServer")
struct LocalPairingServerTests {

    // MARK: - Lifecycle

    @Test("Initial port is zero before start")
    func serverInitialPortIsZero() {
        let server = LocalPairingServer { _, _, _ in }
        #expect(server.port == 0)
    }

    @Test("Start assigns a port")
    func serverStartAssignsPort() async throws {
        let server = LocalPairingServer { _, _, _ in }
        server.start()

        // Wait for listener to become ready
        try await Task.sleep(nanoseconds: 500_000_000)

        #expect(server.port > 0, "Server should bind to a random port > 0")

        server.stop()
    }

    @Test("Stop does not crash after start")
    func serverStopAfterStart() async throws {
        let server = LocalPairingServer { _, _, _ in }
        server.start()

        try await Task.sleep(nanoseconds: 500_000_000)
        #expect(server.port > 0)

        server.stop()
    }

    @Test("Multiple starts do not crash")
    func multipleStarts() async throws {
        let server = LocalPairingServer { _, _, _ in }
        server.start()
        try await Task.sleep(nanoseconds: 200_000_000)
        server.start()
        try await Task.sleep(nanoseconds: 200_000_000)
        server.stop()
    }

    @Test("Stop without start does not crash")
    func stopWithoutStart() {
        let server = LocalPairingServer { _, _, _ in }
        server.stop()
    }

    // MARK: - HTTP Request Handling

    @Test("Valid POST /pair invokes handler with all fields")
    func validPairRequest() async throws {
        let (codeSent, hostSent, modelSent) = try await performPairRequest(
            body: #"{"code":"PAIR123","host":"https://api.octomil.com","model_name":"phi-4-mini"}"#
        )

        #expect(codeSent == "PAIR123")
        #expect(hostSent == "https://api.octomil.com")
        #expect(modelSent == "phi-4-mini")
    }

    @Test("POST /pair with code only sets host and model to nil")
    func pairRequestCodeOnly() async throws {
        let (codeSent, hostSent, modelSent) = try await performPairRequest(
            body: #"{"code":"CODEONLY"}"#
        )

        #expect(codeSent == "CODEONLY")
        #expect(hostSent == nil)
        #expect(modelSent == nil)
    }

    @Test("GET request does not invoke handler")
    func getNonPostRequestIgnored() async throws {
        let called = try await sendRequestExpectingNoCallback(
            method: "GET", path: "/pair", body: nil
        )
        #expect(called == false)
    }

    @Test("POST to wrong path does not invoke handler")
    func wrongPathIgnored() async throws {
        let called = try await sendRequestExpectingNoCallback(
            method: "POST", path: "/other", body: #"{"code":"X"}"#
        )
        #expect(called == false)
    }

    @Test("Invalid JSON body does not invoke handler")
    func invalidJSONIgnored() async throws {
        let called = try await sendRequestExpectingNoCallback(
            method: "POST", path: "/pair", body: "not json"
        )
        #expect(called == false)
    }

    @Test("Missing code field does not invoke handler")
    func missingCodeFieldIgnored() async throws {
        let called = try await sendRequestExpectingNoCallback(
            method: "POST", path: "/pair", body: #"{"host":"H"}"#
        )
        #expect(called == false)
    }

    // MARK: - Golden Harness Routes

    @Test("GET /golden/status returns default status when no provider set")
    func goldenStatusDefault() async throws {
        let server = LocalPairingServer { _, _, _ in }
        server.start()
        try await Task.sleep(nanoseconds: 500_000_000)
        let port = server.port
        #expect(port > 0)

        let (_, body) = try await sendHTTPRequestWithResponse(port: port, method: "GET", path: "/golden/status", body: nil)

        #expect(body.contains("\"phase\""))
        #expect(body.contains("\"idle\""))
        #expect(body.contains("\"paired\""))

        server.stop()
    }

    @Test("GET /golden/status returns custom provider status")
    func goldenStatusCustom() async throws {
        let server = LocalPairingServer { _, _, _ in }
        server.statusProvider = {
            [
                "phase": "active",
                "paired": true,
                "device_registered": true,
                "model_downloaded": true,
                "model_activated": true,
                "active_model": "phi-4-mini",
                "active_version": "1.0.0",
                "model_count": 1,
                "last_error": NSNull(),
            ]
        }
        server.start()
        try await Task.sleep(nanoseconds: 500_000_000)
        let port = server.port
        #expect(port > 0)

        let (_, body) = try await sendHTTPRequestWithResponse(port: port, method: "GET", path: "/golden/status", body: nil)

        #expect(body.contains("\"active\""))
        #expect(body.contains("phi-4-mini"))
        #expect(body.contains("1.0.0"))

        server.stop()
    }

    @Test("POST /golden/reset invokes reset handler")
    func goldenReset() async throws {
        var resetCalled = false
        let server = LocalPairingServer { _, _, _ in }
        server.resetHandler = {
            resetCalled = true
        }
        server.start()
        try await Task.sleep(nanoseconds: 500_000_000)
        let port = server.port
        #expect(port > 0)

        let (_, body) = try await sendHTTPRequestWithResponse(port: port, method: "POST", path: "/golden/reset", body: nil)

        try await Task.sleep(nanoseconds: 500_000_000)

        #expect(body.contains("\"ok\""))
        #expect(resetCalled == true)

        server.stop()
    }

    @Test("POST /golden/reset returns noop when no handler set")
    func goldenResetNoop() async throws {
        let server = LocalPairingServer { _, _, _ in }
        server.start()
        try await Task.sleep(nanoseconds: 500_000_000)
        let port = server.port
        #expect(port > 0)

        let (_, body) = try await sendHTTPRequestWithResponse(port: port, method: "POST", path: "/golden/reset", body: nil)

        #expect(body.contains("\"noop\""))

        server.stop()
    }

    // MARK: - Helpers

    /// Start a server, send a valid POST /pair, and return the received values.
    private func performPairRequest(body: String) async throws -> (code: String?, host: String?, model: String?) {
        var receivedCode: String?
        var receivedHost: String?
        var receivedModelName: String?

        let server = LocalPairingServer { code, host, modelName in
            receivedCode = code
            receivedHost = host
            receivedModelName = modelName
        }
        server.start()
        try await Task.sleep(nanoseconds: 500_000_000)

        let port = server.port
        #expect(port > 0)

        try await sendHTTPRequest(port: port, method: "POST", path: "/pair", body: body)

        // Give the server time to process
        try await Task.sleep(nanoseconds: 500_000_000)

        server.stop()
        return (receivedCode, receivedHost, receivedModelName)
    }

    /// Start a server, send a request, and verify the handler was NOT called.
    private func sendRequestExpectingNoCallback(method: String, path: String, body: String?) async throws -> Bool {
        var handlerCalled = false

        let server = LocalPairingServer { _, _, _ in
            handlerCalled = true
        }
        server.start()
        try await Task.sleep(nanoseconds: 500_000_000)

        try await sendHTTPRequest(port: server.port, method: method, path: path, body: body)

        // Give the server time to process (or not)
        try await Task.sleep(nanoseconds: 500_000_000)

        server.stop()
        return handlerCalled
    }

    /// Sends a raw HTTP request and returns (statusLine, body).
    private func sendHTTPRequestWithResponse(port: UInt16, method: String, path: String, body: String?) async throws -> (String, String) {
        let connection = NWConnection(
            host: .ipv4(.loopback),
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    continuation.resume()
                case .failed(let error):
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
        }

        var request = "\(method) \(path) HTTP/1.1\r\nHost: localhost:\(port)\r\n"
        if let body {
            request += "Content-Type: application/json\r\n"
            request += "Content-Length: \(body.utf8.count)\r\n"
            request += "\r\n"
            request += body
        } else {
            request += "\r\n"
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: request.data(using: .utf8), completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }

        // Read response
        let responseData = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: data ?? Data())
                }
            }
        }

        connection.cancel()

        let responseString = String(data: responseData, encoding: .utf8) ?? ""
        // Split into status line and body
        let parts = responseString.components(separatedBy: "\r\n\r\n")
        let statusLine = parts.first?.components(separatedBy: "\r\n").first ?? ""
        let responseBody = parts.count > 1 ? parts[1] : ""
        return (statusLine, responseBody)
    }

    /// Sends a raw HTTP request to localhost at the given port.
    private func sendHTTPRequest(port: UInt16, method: String, path: String, body: String?) async throws {
        let connection = NWConnection(
            host: .ipv4(.loopback),
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    continuation.resume()
                case .failed(let error):
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
        }

        var request = "\(method) \(path) HTTP/1.1\r\nHost: localhost:\(port)\r\n"
        if let body {
            request += "Content-Type: application/json\r\n"
            request += "Content-Length: \(body.utf8.count)\r\n"
            request += "\r\n"
            request += body
        } else {
            request += "\r\n"
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: request.data(using: .utf8), completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }

        connection.cancel()
    }
}
