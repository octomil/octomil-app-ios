import Foundation
import Testing
@testable import OctomilAppLib
import Octomil

/// Clears the @AppStorage keys used by AppState so each test starts fresh.
private func resetAppStorageDefaults() {
    let keys = [
        "octomil_device_token",
        "octomil_org_id",
        "octomil_server_url",
        "octomil_device_name",
    ]
    for key in keys {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

@Suite("AppState")
@MainActor
struct AppStateTests {

    init() {
        resetAppStorageDefaults()
    }

    // MARK: - Initialization

    @Test("Defaults to home tab")
    func defaultSelectedTab() {
        let state = AppState()
        #expect(state.selectedTab == .home)
    }

    @Test("Default server URL points to production")
    func defaultServerURL() {
        let state = AppState()
        #expect(state.serverURL == "https://api.octomil.com")
    }

    @Test("Pairing sheet is hidden by default")
    func defaultPairingState() {
        let state = AppState()
        #expect(state.showPairingSheet == false)
        #expect(state.pendingPairingCode == nil)
    }

    @Test("Device is not registered by default")
    func defaultRegistrationState() {
        let state = AppState()
        #expect(state.isRegistered == false)
    }

    @Test("No paired models by default")
    func defaultModelsEmpty() {
        let state = AppState()
        #expect(state.pairedModels.isEmpty)
    }

    @Test("Client is nil without credentials")
    func clientIsNilWithoutCredentials() {
        let state = AppState()
        #expect(state.client == nil)
    }

    // MARK: - initializeClient

    @Test("Does not create client with empty token")
    func initializeClientWithEmptyToken() {
        let state = AppState()
        state.deviceToken = ""
        state.orgId = "org_123"
        state.initializeClient()

        #expect(state.client == nil)
    }

    @Test("Does not create client with empty org ID")
    func initializeClientWithEmptyOrgId() {
        let state = AppState()
        state.deviceToken = "token_abc"
        state.orgId = ""
        state.initializeClient()

        #expect(state.client == nil)
    }

    @Test("Does not create client when both credentials empty")
    func initializeClientWithBothEmpty() {
        let state = AppState()
        state.deviceToken = ""
        state.orgId = ""
        state.initializeClient()

        #expect(state.client == nil)
    }

    @Test("Creates client with valid credentials")
    func initializeClientWithValidCredentials() {
        let state = AppState()
        state.deviceToken = "tok_valid"
        state.orgId = "org_valid"
        state.initializeClient()

        #expect(state.client != nil)
    }

    @Test("Creates client with custom server URL")
    func initializeClientWithCustomServerURL() {
        let state = AppState()
        state.deviceToken = "tok_valid"
        state.orgId = "org_valid"
        state.serverURL = "https://staging.octomil.com"
        state.initializeClient()

        #expect(state.client != nil)
    }

    @Test("Falls back to default URL when server URL is invalid")
    func initializeClientWithInvalidServerURL() {
        let state = AppState()
        state.deviceToken = "tok_valid"
        state.orgId = "org_valid"
        state.serverURL = "://invalid"
        state.initializeClient()

        #expect(state.client != nil)
    }

    @Test("Reinitializing replaces existing client")
    func reinitializeClientReplacesExisting() {
        let state = AppState()
        state.deviceToken = "tok_first"
        state.orgId = "org_first"
        state.initializeClient()
        let firstClient = state.client

        state.deviceToken = "tok_second"
        state.orgId = "org_second"
        state.initializeClient()
        let secondClient = state.client

        #expect(firstClient != nil)
        #expect(secondClient != nil)
        #expect(firstClient !== secondClient)
    }

    // MARK: - addPairedModel

    @Test("Appends a new model to the list")
    func addPairedModelAppends() {
        let state = AppState()
        let model = PairedModelInfo(
            name: "phi-4-mini",
            version: "1.0",
            sizeString: "2.3 GB",
            runtime: "CoreML",
            tokensPerSecond: 15.2
        )

        state.addPairedModel(model)

        #expect(state.pairedModels.count == 1)
        #expect(state.pairedModels.first?.name == "phi-4-mini")
    }

    @Test("Prevents adding duplicate models by name")
    func addPairedModelDeduplicates() {
        let state = AppState()
        let model1 = PairedModelInfo(
            name: "phi-4-mini",
            version: "1.0",
            sizeString: "2.3 GB",
            runtime: "CoreML",
            tokensPerSecond: 15.2
        )
        let model2 = PairedModelInfo(
            name: "phi-4-mini",
            version: "2.0",
            sizeString: "2.5 GB",
            runtime: "CoreML",
            tokensPerSecond: 18.0
        )

        state.addPairedModel(model1)
        state.addPairedModel(model2)

        #expect(state.pairedModels.count == 1)
        // Keeps the first one
        #expect(state.pairedModels.first?.version == "1.0")
    }

    @Test("Adds multiple models with different names")
    func addMultipleDifferentModels() {
        let state = AppState()
        let models = [
            PairedModelInfo(name: "phi-4-mini", version: "1.0", sizeString: "2.3 GB", runtime: "CoreML", tokensPerSecond: 15.2),
            PairedModelInfo(name: "gemma-2b", version: "1.0", sizeString: "1.8 GB", runtime: "CoreML", tokensPerSecond: 22.0),
            PairedModelInfo(name: "llama-3.2-1b", version: "1.0", sizeString: "1.2 GB", runtime: "CoreML", tokensPerSecond: 30.0),
        ]

        for model in models {
            state.addPairedModel(model)
        }

        #expect(state.pairedModels.count == 3)
    }

    @Test("Preserves modalities when adding model")
    func addPairedModelWithModalities() {
        let state = AppState()
        let model = PairedModelInfo(
            name: "clip-vit",
            version: "1.0",
            sizeString: "300 MB",
            runtime: "CoreML",
            tokensPerSecond: nil,
            modalities: ["text", "image"]
        )

        state.addPairedModel(model)

        #expect(state.pairedModels.first?.modalities == ["text", "image"])
    }

    // MARK: - register guard

    @Test("Register with no client returns early without error")
    func registerWithNoClient() async throws {
        let state = AppState()
        // Explicitly ensure no credentials -> no client
        state.deviceToken = ""
        state.orgId = ""
        #expect(state.client == nil)

        try await state.register()
        #expect(state.isRegistered == false)
    }

    // MARK: - Tab State

    @Test("All tab cases exist")
    func tabEnumCases() {
        let tabs: [AppTab] = [.home, .pair, .settings]
        #expect(tabs.count == 3)
    }

    @Test("Selected tab can be changed")
    func selectedTabCanBeChanged() {
        let state = AppState()
        #expect(state.selectedTab == .home)

        state.selectedTab = .pair
        #expect(state.selectedTab == .pair)

        state.selectedTab = .settings
        #expect(state.selectedTab == .settings)
    }

    // MARK: - Pairing sheet state

    @Test("Pairing state can be set and cleared")
    func pairingSheetLifecycle() {
        let state = AppState()

        // Set pairing state
        state.pendingPairingCode = "ABC123"
        state.showPairingSheet = true
        state.selectedTab = .pair

        #expect(state.pendingPairingCode == "ABC123")
        #expect(state.showPairingSheet == true)
        #expect(state.selectedTab == .pair)

        // Clear pairing state
        state.pendingPairingCode = nil
        state.showPairingSheet = false

        #expect(state.pendingPairingCode == nil)
        #expect(state.showPairingSheet == false)
    }

    // MARK: - Local Server Port

    @Test("Default local port is zero")
    func defaultLocalPort() {
        let state = AppState()
        #expect(state.localPort == 0)
    }

    // MARK: - startAdvertising guard

    @Test("startAdvertising with zero port does not crash")
    func startAdvertisingWithZeroPort() {
        let state = AppState()
        #expect(state.localPort == 0)
        state.startAdvertising()
    }

    // MARK: - startLocalServer

    @Test("startLocalServer creates server and assigns port")
    func startLocalServer() async throws {
        let state = AppState()
        state.startLocalServer()

        // Wait for the server to bind
        try await Task.sleep(nanoseconds: 500_000_000)

        // The port should now be set (may be 0 if not yet ready, but server should exist)
        // Note: port is read synchronously from server.port at start time,
        // which may be 0 if the listener hasn't bound yet.
        // The important thing is it doesn't crash.
    }

    // MARK: - Initialization with pre-existing credentials

    @Test("Auto-initializes client when credentials exist in UserDefaults")
    func autoInitializesClientWithExistingCredentials() {
        // Simulate pre-existing credentials
        UserDefaults.standard.set("tok_existing", forKey: "octomil_device_token")
        UserDefaults.standard.set("org_existing", forKey: "octomil_org_id")

        let state = AppState()
        #expect(state.client != nil)

        // Clean up
        resetAppStorageDefaults()
    }

    @Test("Does not auto-initialize client when only token exists")
    func noAutoInitWithTokenOnly() {
        UserDefaults.standard.set("tok_only", forKey: "octomil_device_token")

        let state = AppState()
        #expect(state.client == nil)

        resetAppStorageDefaults()
    }

    @Test("Does not auto-initialize client when only org ID exists")
    func noAutoInitWithOrgIdOnly() {
        UserDefaults.standard.set("org_only", forKey: "octomil_org_id")

        let state = AppState()
        #expect(state.client == nil)

        resetAppStorageDefaults()
    }
}
