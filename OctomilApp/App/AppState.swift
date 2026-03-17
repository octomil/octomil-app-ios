import SwiftUI
import Octomil
import Network

enum AppTab {
    case home, pair, settings
}

/// Shared application state managing client, models, pairing, and local server.
@MainActor
final class AppState: ObservableObject {
    @Published var client: OctomilClient?
    @Published var pairedModels: [PairedModelInfo] = []
    @Published var isRegistered = false
    @Published var showPairingSheet = false
    @Published var pendingPairingCode: String?
    @Published var selectedTab: AppTab = .home

    @AppStorage("octomil_device_token") var deviceToken: String = ""
    @AppStorage("octomil_org_id") var orgId: String = ""
    @AppStorage("octomil_server_url") var serverURL: String = "https://api.octomil.com"
    @AppStorage("octomil_device_name") var deviceName: String = ""

    private var localServer: LocalPairingServer?
    private var advertiser: NWListener?

    // No DeviceMetadata() — it lacks a public init. Collect device info inline.

    /// The mDNS-advertised port for the local pairing server.
    private(set) var localPort: UInt16 = 0

    init() {
        if deviceName.isEmpty {
            #if canImport(UIKit)
            deviceName = UIDevice.current.name
            #else
            deviceName = Host.current().localizedName ?? "Mac"
            #endif
        }
        if !deviceToken.isEmpty, !orgId.isEmpty {
            initializeClient()
        }
    }

    func initializeClient() {
        guard !deviceToken.isEmpty, !orgId.isEmpty else { return }
        let baseURL = URL(string: serverURL) ?? OctomilClient.defaultServerURL
        let auth = AuthConfig.deviceToken(
            deviceId: orgId,
            bootstrapToken: deviceToken,
            serverURL: baseURL
        )
        client = OctomilClient(auth: auth)
    }

    func register() async throws {
        guard let client else { return }
        _ = try await client.register(deviceId: nil, appVersion: nil, metadata: nil)
        isRegistered = client.isRegistered
    }

    func addPairedModel(_ model: PairedModelInfo) {
        if !pairedModels.contains(where: { $0.name == model.name }) {
            pairedModels.append(model)
        }
    }

    // MARK: - Local Pairing Server

    func startLocalServer() {
        let server = LocalPairingServer { [weak self] code, host, modelName in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let host, !host.isEmpty {
                    self.serverURL = host
                    self.initializeClient()
                }
                self.pendingPairingCode = code
                self.showPairingSheet = true
                self.selectedTab = .pair
            }
        }
        server.start()
        localServer = server
        localPort = server.port
    }

    // MARK: - mDNS Advertising

    func startAdvertising() {
        guard localPort > 0 else { return }

        let name = deviceName
        let port = localPort
        #if canImport(UIKit)
        let deviceIdString = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        #else
        let deviceIdString = UUID().uuidString
        #endif

        var txtDict: [String: String] = [:]
        txtDict["device_name"] = name
        txtDict["platform"] = "ios"
        txtDict["device_id"] = deviceIdString
        let txtData = NetService.data(fromTXTRecord: txtDict.mapValues { $0.data(using: .utf8) ?? Data() })
        let txtRecord = NWTXTRecord(txtData)

        do {
            let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
            listener.service = NWListener.Service(
                name: name,
                type: "_octomil._tcp",
                txtRecord: txtRecord
            )
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    print("[mDNS] Advertising \(name) on port \(port)")
                case .failed(let error):
                    print("[mDNS] Failed: \(error)")
                default:
                    break
                }
            }
            listener.newConnectionHandler = { connection in
                connection.cancel()
            }
            listener.start(queue: .global())
            advertiser = listener
        } catch {
            print("[mDNS] Could not start advertiser: \(error)")
        }
    }
}
