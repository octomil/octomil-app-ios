// Tests for AppProfile / AppProfileResolver in the companion app.
//
// Mirrors the cross-repo profile suite (octomil-python, octomil-node,
// octomil-browser, octomil-ios SDK, octomil-android). The app's
// AppProfile is a smaller subset because it only resolves the
// FIRST-RUN default server URL — users override it via Settings
// after that.

import Foundation
import Testing
@testable import OctomilAppLib

@Suite("AppProfile")
struct AppProfileTests {

    // MARK: - rawValues match SDK

    @Test func rawValuesMatchSDKManifestNames() {
        #expect(AppProfile.production.rawValue == "production")
        #expect(AppProfile.staging.rawValue == "staging")
        #expect(AppProfile.dev.rawValue == "dev")
    }

    // MARK: - URL constants

    @Test func productionURLDoesNotContainStaging() {
        // Critical safety pin — if production URL ever drifts to a
        // staging-shaped URL, the app boots into staging by default
        // for every user.
        let url = AppProfile.production.defaultHostURL.absoluteString
        #expect(!url.contains("staging"))
        #expect(url == "https://api.octomil.com")
    }

    @Test func stagingURLIsDistinct() {
        #expect(AppProfile.staging.defaultHostURL.absoluteString == "https://api.staging.octomil.com")
        #expect(AppProfile.staging.defaultHostURL != AppProfile.production.defaultHostURL)
    }

    @Test func devURLIsLocalhost() {
        #expect(AppProfile.dev.defaultHostURL.absoluteString.hasPrefix("http://localhost"))
    }

    @Test func eachProfileHasDistinctURL() {
        let urls = Set(AppProfile.allCases.map(\.defaultHostURL))
        #expect(urls.count == AppProfile.allCases.count)
    }

    // MARK: - displayName

    @Test func displayNamesAreOperatorFriendly() {
        #expect(AppProfile.production.displayName == "Production")
        #expect(AppProfile.staging.displayName == "Staging")
        #expect(AppProfile.dev.displayName == "Local Dev")
    }

    // MARK: - AppProfile.from

    @Test func fromAcceptsCanonicalNames() {
        #expect(AppProfile.from("production") == .production)
        #expect(AppProfile.from("staging") == .staging)
        #expect(AppProfile.from("dev") == .dev)
    }

    @Test func fromIsCaseInsensitive() {
        #expect(AppProfile.from("STAGING") == .staging)
        #expect(AppProfile.from("Staging") == .staging)
    }

    @Test func fromAcceptsAliases() {
        #expect(AppProfile.from("prod") == .production)
        #expect(AppProfile.from("stg") == .staging)
    }

    @Test func fromReturnsNilForUnknown() {
        #expect(AppProfile.from("preview") == nil)
        #expect(AppProfile.from("") == nil)
    }

    // MARK: - AppProfileResolver — env

    @Test func resolveDefaultPicksStagingFromEnv() {
        let p = AppProfileResolver.resolveDefault(
            environment: ["OCTOMIL_PROFILE": "staging"]
        )
        #expect(p == .staging)
    }

    @Test func resolveDefaultEmptyProfileFallsThrough() {
        let p = AppProfileResolver.resolveDefault(environment: ["OCTOMIL_PROFILE": ""])
        #expect(p == .production)
    }

    @Test func resolveDefaultIsCaseInsensitive() {
        let p = AppProfileResolver.resolveDefault(environment: ["OCTOMIL_PROFILE": "STAGING"])
        #expect(p == .staging)
    }

    @Test func resolveDefaultUnknownProfileFallsThrough() {
        // Unknown profile in env shouldn't crash the app — fall
        // through silently to the production default. Boot must
        // never throw.
        let p = AppProfileResolver.resolveDefault(environment: ["OCTOMIL_PROFILE": "preview"])
        #expect(p == .production)
    }

    // MARK: - AppProfileResolver — URL inference

    @Test func resolveDefaultInfersStagingFromAPIBase() {
        let p = AppProfileResolver.resolveDefault(
            environment: ["OCTOMIL_API_BASE": "https://api.staging.octomil.com/v1"]
        )
        #expect(p == .staging)
    }

    @Test func resolveDefaultInfersProductionFromAPIURL() {
        let p = AppProfileResolver.resolveDefault(
            environment: ["OCTOMIL_API_URL": "https://api.octomil.com"]
        )
        #expect(p == .production)
    }

    @Test func resolveDefaultInfersDevFromLocalhost() {
        let p = AppProfileResolver.resolveDefault(
            environment: ["OCTOMIL_API_BASE": "http://localhost:8000"]
        )
        #expect(p == .dev)
    }

    @Test func resolveDefaultEnvOverridesURLInference() {
        let p = AppProfileResolver.resolveDefault(
            environment: [
                "OCTOMIL_PROFILE": "staging",
                "OCTOMIL_API_BASE": "https://api.octomil.com",
            ]
        )
        #expect(p == .staging)
    }

    @Test func resolveDefaultUnmatchedURLFallsThrough() {
        let p = AppProfileResolver.resolveDefault(
            environment: ["OCTOMIL_API_BASE": "https://example.com/api"]
        )
        #expect(p == .production)
    }

    // MARK: - default

    @Test func resolveDefaultNoSignalsReturnsProduction() {
        let p = AppProfileResolver.resolveDefault(environment: [:])
        #expect(p == .production)
    }

    // MARK: - defaultServerURLString convenience

    @Test func defaultServerURLStringPicksStaging() {
        let s = AppProfileResolver.defaultServerURLString(
            environment: ["OCTOMIL_PROFILE": "staging"]
        )
        #expect(s == "https://api.staging.octomil.com")
    }

    @Test func defaultServerURLStringDefaultsToProduction() {
        let s = AppProfileResolver.defaultServerURLString(environment: [:])
        #expect(s == "https://api.octomil.com")
    }

    // MARK: - Hostile-URL inference safety (codex post-debate B1)

    @Test func markerInQueryStringDoesNotSpoofProfile() {
        let p = AppProfileResolver.resolveDefault(
            environment: ["OCTOMIL_API_BASE": "https://evil.test/?next=api.staging.octomil.com"]
        )
        #expect(p == .production)
    }

    @Test func markerInPathDoesNotSpoofProfile() {
        let p = AppProfileResolver.resolveDefault(
            environment: ["OCTOMIL_API_BASE": "https://evil.test/api.octomil.com/v1"]
        )
        #expect(p == .production)
    }

    @Test func markerInUserinfoDoesNotSpoofProfile() {
        let p = AppProfileResolver.resolveDefault(
            environment: ["OCTOMIL_API_BASE": "https://api.staging.octomil.com@evil.test/v1"]
        )
        // URLComponents.host is evil.test.
        #expect(p == .production)
    }

    @Test func superdomainDoesNotSpoofProduction() {
        let p = AppProfileResolver.resolveDefault(
            environment: ["OCTOMIL_API_BASE": "https://api.octomil.com.evil.test/v1"]
        )
        #expect(p == .production)
    }

    @Test func unparseableURLFallsThroughSafely() {
        let p = AppProfileResolver.resolveDefault(
            environment: ["OCTOMIL_API_BASE": "not a url"]
        )
        #expect(p == .production)
    }

    // MARK: - Whitespace fallback (codex post-debate N1)

    @Test func whitespaceAPIBaseFallsBackToAPIURL() {
        let p = AppProfileResolver.resolveDefault(
            environment: [
                "OCTOMIL_API_BASE": "   ",
                "OCTOMIL_API_URL": "https://api.staging.octomil.com",
            ]
        )
        #expect(p == .staging)
    }
}
