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
    /// Resource kind → filename mapping for resolving individual files within the model directory.
    let resourceBindings: [String: String]?

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
        self.resourceBindings = pairedModel.resourceBindings.isEmpty ? nil : pairedModel.resourceBindings
    }

    var compiledModelURL: URL? {
        modelPath.map { URL(fileURLWithPath: $0) }
    }

    /// Whether the model directory still exists on disk.
    /// Returns `false` when iOS has purged `Library/Caches/` or the app was reinstalled.
    var isAvailableOnDisk: Bool {
        guard let path = modelPath else { return false }
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
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

    /// Map server-provided modalities to capability.
    static func inferCapability(
        from runtime: String,
        modalities: [String]? = nil
    ) -> (ModelCapability, Bool) {
        let rt = runtime.lowercased()
        let set = Set(modalities?.map { $0.lowercased() } ?? [])

        if set.contains("audio") || set.contains("speech") || set.contains("voice") {
            let streaming = (rt == "sherpa" || rt == "sherpa-onnx")
            return (.transcription, streaming)
        }
        return (.chat, true)
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
    @AppStorage("octomil_server_url") var serverURL: String = "https://api.octomil.com" {
        didSet {
            // Strip /api/v1 suffix — APIClient appends its own path prefix
            if serverURL.hasSuffix("/api/v1") {
                serverURL = String(serverURL.dropLast("/api/v1".count))
            }
        }
    }
    @AppStorage("octomil_device_name") var deviceName: String = ""

    private static let storedModelsKey = "octomil_stored_models"

    private var localServer: LocalPairingServer?
    private var advertiser: NWListener?

    /// The mDNS-advertised port for the local pairing server.
    private(set) var localPort: UInt16 = 0

    init() {
        // Fix persisted server URLs that include /api/v1 from older deep links
        if serverURL.hasSuffix("/api/v1") {
            serverURL = String(serverURL.dropLast("/api/v1".count))
        }

        // Restore credentials from Keychain if UserDefaults were wiped (reinstall)
        if deviceToken.isEmpty, let kcToken = KeychainHelper.read(key: "device_token") {
            deviceToken = kcToken
        }
        if orgId.isEmpty, let kcOrg = KeychainHelper.read(key: "org_id") {
            orgId = kcOrg
        }
        if serverURL == "https://api.octomil.com",
           let kcURL = KeychainHelper.read(key: "server_url"),
           kcURL != "https://api.octomil.com" {
            serverURL = kcURL
        }

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

    /// Persist credentials to Keychain so they survive app reinstall.
    func saveToKeychain() {
        if !deviceToken.isEmpty { KeychainHelper.save(key: "device_token", value: deviceToken) }
        if !orgId.isEmpty { KeychainHelper.save(key: "org_id", value: orgId) }
        if serverURL != "https://api.octomil.com" {
            KeychainHelper.save(key: "server_url", value: serverURL)
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
    /// Skips registration if the model directory no longer exists on disk
    /// (e.g. after an app reinstall wiped Library/Caches/).
    private func registerRuntime(for model: StoredModel) {
        guard let url = model.compiledModelURL else { return }
        // Verify the model directory actually exists before registering.
        // The native sherpa-onnx engine crashes (not throws) on invalid paths.
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
              isDir.boolValue else {
            return
        }
        ModelRuntimeRegistry.shared.registerModel(
            name: model.name,
            fileURL: url,
            engine: Engine(executor: model.runtime),
            resourceBindings: model.resourceBindings ?? [:]
        )
    }

    private func persistStoredModels() {
        guard let data = try? JSONEncoder().encode(storedModels) else { return }
        UserDefaults.standard.set(data, forKey: Self.storedModelsKey)
    }

    // MARK: - Auto-Recovery

    /// Triggers SDK reconciliation to recover missing model files, then
    /// syncs local storedModels with the SDK's metadata store.
    ///
    /// The SDK's ``ArtifactReconciler`` handles downloading via the server's
    /// desired-state endpoint and multi-file artifact support. This method
    /// just bridges the SDK's record paths back into the app's StoredModel list.
    func recoverAndSyncModels() async {
        guard let client else { return }

        // 1. Let the SDK reconciler download any missing artifacts
        try? await client.recoverModels()

        // 2. Sync storedModel paths from SDK metadata
        syncModelPathsFromSDK()
    }

    /// Updates storedModels file paths from the SDK's installed model metadata.
    ///
    /// After the SDK reconciler recovers models (possibly to a different directory
    /// than the original pairing path), this method updates the app's StoredModel
    /// entries to point at the SDK's artifact directory and re-registers runtimes.
    func syncModelPathsFromSDK() {
        guard let client else { return }
        let sdkRecords = client.installedModels()

        var changed = false
        for (index, stored) in storedModels.enumerated() {
            guard let record = sdkRecords.first(where: { $0.modelId == stored.name }) else { continue }

            // Update path if SDK recovered to a different location, or if file was missing
            let sdkPath = record.filePath
            if stored.modelPath != sdkPath || !stored.isAvailableOnDisk {
                let updated = StoredModel(
                    from: PairedModelInfo(
                        name: stored.name,
                        version: stored.version,
                        sizeString: stored.sizeString,
                        runtime: stored.runtime,
                        tokensPerSecond: stored.tokensPerSecond,
                        compiledModelURL: URL(fileURLWithPath: sdkPath),
                        resourceBindings: record.resourceBindings ?? stored.resourceBindings ?? [:]
                    ),
                    capability: stored.capability,
                    supportsStreaming: stored.supportsStreaming
                )
                storedModels[index] = updated
                registerRuntime(for: updated)
                changed = true
            }
        }
        if changed { persistStoredModels() }
    }

    // MARK: - Local Pairing Server

    func startLocalServer() async {
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

        #if DEBUG
        server.statusProvider = { [weak self] in
            self?.buildGoldenStatus() ?? LocalPairingServer.defaultStatusDict
        }
        server.resetHandler = { [weak self] in
            Task { @MainActor [weak self] in
                self?.resetForGoldenPath()
            }
        }
        server.testHandler = GoldenTestRunner(
            models: { [weak self] in self?.storedModels ?? [] },
            client: { [weak self] in self?.client }
        )
        #endif

        await server.startAsync()
        localServer = server
        localPort = server.port
    }

    // MARK: - Golden Path Harness (debug only)

    #if DEBUG
    private func buildGoldenStatus() -> [String: Any] {
        let paired = !deviceToken.isEmpty
        let registered = client != nil
        let onDisk = storedModels.contains { $0.isAvailableOnDisk }
        let firstModel = storedModels.first

        let phase: String
        if !paired {
            phase = "idle"
        } else if storedModels.isEmpty {
            phase = "pairing"
        } else if !onDisk {
            phase = "downloading"
        } else {
            phase = "active"
        }

        return [
            "phase": phase,
            "paired": paired,
            "device_registered": registered,
            "model_downloaded": onDisk,
            "model_activated": onDisk && registered,
            "active_model": firstModel?.name as Any? ?? NSNull(),
            "active_version": firstModel?.version as Any? ?? NSNull(),
            "model_count": storedModels.count,
            "last_error": NSNull(),
        ]
    }

    private func resetForGoldenPath() {
        // Clear credentials
        deviceToken = ""
        orgId = ""
        serverURL = "https://api.octomil.com"
        client = nil

        // Clear Keychain
        KeychainHelper.delete(key: "device_token")
        KeychainHelper.delete(key: "org_id")
        KeychainHelper.delete(key: "server_url")

        // Clear models
        storedModels.removeAll()
        pairedModels.removeAll()
        persistStoredModels()

        // Delete cached model files
        let fm = FileManager.default
        if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let modelsDir = appSupport.appendingPathComponent("ai.octomil.models", isDirectory: true)
            try? fm.removeItem(at: modelsDir)
        }
    }
    #endif

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
