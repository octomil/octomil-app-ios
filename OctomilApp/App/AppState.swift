import SwiftUI
import OctomilClient
import Network

/// Shared application state managing client, models, pairing, and local server.
@MainActor
final class AppState: ObservableObject {
    @Published var client: OctomilClient?
    @Published var downloadedModels: [OctomilModel] = []
    @Published var isRegistered = false
    @Published var showPairingSheet = false
    @Published var pendingPairingCode: String?
    @Published var selectedTab: AppTab = .home

    @AppStorage("octomil_api_key") var apiKey: String = ""
    @AppStorage("octomil_org_id") var orgId: String = ""
    @AppStorage("octomil_server_url") var serverURL: String = "https://api.octomil.com/api/v1"
    @AppStorage("octomil_device_name") var deviceName: String = ""

    private var localServer: LocalPairingServer?
    private var advertiser: NWListener?

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
        if !apiKey.isEmpty, !orgId.isEmpty {
            initializeClient()
        }
    }

    func initializeClient() {
        guard !apiKey.isEmpty, !orgId.isEmpty else { return }
        let baseURL = URL(string: serverURL) ?? URL(string: "https://api.octomil.com/api/v1")!
        client = OctomilClient(apiKey: apiKey, orgId: orgId, baseURL: baseURL)
    }

    func register() async throws {
        guard let client else { return }
        try await client.register()
        isRegistered = true
    }

    func addModel(_ model: OctomilModel) {
        if !downloadedModels.contains(where: { $0.modelId == model.modelId }) {
            downloadedModels.append(model)
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

        let txtRecord = NWTXTRecord()
        txtRecord[.init("device_name")] = .string(deviceName)
        txtRecord[.init("platform")] = .string("ios")
        txtRecord[.init("device_id")] = .string(
            UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        )

        do {
            let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: localPort)!)
            listener.service = NWListener.Service(
                name: deviceName,
                type: "_octomil._tcp",
                txtRecord: txtRecord
            )
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    print("[mDNS] Advertising \(self.deviceName) on port \(self.localPort)")
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
