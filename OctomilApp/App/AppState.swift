import SwiftUI
import Octomil
import Network

enum AppTab {
    case home, pair, settings
}

// MARK: - Model Capability

enum ModelCapability: String, Codable {
    case transcription
    case chat
    case keyboardPrediction = "keyboard_prediction"
}

// MARK: - Stored Model

/// Persistable model info with capability routing data.
struct StoredModel: Codable, Identifiable {
    let id: String
    let name: String
    let version: String
    let sizeString: String
    let runtime: String
    let tokensPerSecond: Double?
    let capability: ModelCapability
    let supportsStreaming: Bool
    let modelPath: String?

    init(from pairedModel: PairedModelInfo, capability: ModelCapability, supportsStreaming: Bool) {
        self.id = pairedModel.name
        self.name = pairedModel.name
        self.version = pairedModel.version
        self.sizeString = pairedModel.sizeString
        self.runtime = pairedModel.runtime
        self.tokensPerSecond = pairedModel.tokensPerSecond
        self.capability = capability
        self.supportsStreaming = supportsStreaming
        self.modelPath = pairedModel.compiledModelURL?.path
    }

    var compiledModelURL: URL? {
        modelPath.map { URL(fileURLWithPath: $0) }
    }

    var capabilityLabel: String {
        switch capability {
        case .transcription: return "Transcription"
        case .chat: return "Chat"
        case .keyboardPrediction: return "Prediction"
        }
    }

    var capabilityIcon: String {
        switch capability {
        case .transcription: return "waveform"
        case .chat: return "bubble.left.and.bubble.right"
        case .keyboardPrediction: return "text.cursor"
        }
    }

    /// Infer capability from the model's runtime/executor.
    static func inferCapability(from runtime: String) -> (ModelCapability, Bool) {
        switch runtime.lowercased() {
        case "sherpa", "sherpa-onnx":
            return (.transcription, true)
        case "whisper", "whisper.cpp":
            return (.transcription, false)
        case "mlx", "llama.cpp", "llamacpp":
            return (.chat, true)
        default:
            return (.chat, true)
        }
    }
}

/// Shared application state managing client, models, pairing, and local server.
@MainActor
final class AppState: ObservableObject {
    @Published var client: OctomilClient?
    @Published var pairedModels: [PairedModelInfo] = []
    @Published var storedModels: [StoredModel] = []
    @Published var isRegistered = false
    @Published var showPairingSheet = false
    @Published var pendingPairingCode: String?
    @Published var selectedTab: AppTab = .home

    @AppStorage("octomil_device_token") var deviceToken: String = ""
    @AppStorage("octomil_org_id") var orgId: String = ""
    @AppStorage("octomil_server_url") var serverURL: String = "https://api.octomil.com"
    @AppStorage("octomil_device_name") var deviceName: String = ""

    private static let storedModelsKey = "octomil_stored_models"

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
        loadStoredModels()
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

    func addStoredModel(_ model: StoredModel) {
        if let index = storedModels.firstIndex(where: { $0.name == model.name }) {
            storedModels[index] = model
        } else {
            storedModels.append(model)
        }
        registerRuntime(for: model)
        persistStoredModels()
    }

    func removeStoredModel(_ model: StoredModel) {
        storedModels.removeAll { $0.id == model.id }
        pairedModels.removeAll { $0.name == model.name }
        persistStoredModels()
    }

    // MARK: - Persistence

    private func loadStoredModels() {
        guard let data = UserDefaults.standard.data(forKey: Self.storedModelsKey),
              let models = try? JSONDecoder().decode([StoredModel].self, from: data) else {
            return
        }
        storedModels = models
        for model in models {
            registerRuntime(for: model)
        }
    }

    /// Register a ``LocalFileModelRuntime`` for a stored model so that
    /// ``ModelRuntimeRegistry.shared.resolve(modelId:)`` can find it.
    private func registerRuntime(for model: StoredModel) {
        guard let url = model.compiledModelURL else { return }
        ModelRuntimeRegistry.shared.register(family: model.name) { _ in
            LocalFileModelRuntime(modelId: model.name, fileURL: url)
        }
    }

    private func persistStoredModels() {
        guard let data = try? JSONEncoder().encode(storedModels) else { return }
        UserDefaults.standard.set(data, forKey: Self.storedModelsKey)
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
