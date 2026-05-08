// Companion-app environment profile resolution.
//
// The OctomilApp companion app talks to one of three Octomil
// environments (production, staging, dev). This file is the
// single source of truth FOR THE APP for which environment to
// default to when the user hasn't pinned a custom server URL.
//
// Why duplicate SDK Profile?
// The iOS SDK ships its own OctomilProfile / OctomilProfileResolver
// (see octomil-ios PR #204). Once that PR merges and is published
// to a tag this app pins, this file should be replaced with a
// thin wrapper around `Octomil.OctomilProfileResolver`. Until then
// — and to land this companion-app change INDEPENDENTLY of the
// SDK PR — the app keeps its own copy of the URL constants. **Any
// change here MUST be mirrored in the SDK** or the SDK boots into
// a different env than the app's UI shows.
//
// See octomil-app-ios PR description for the cross-repo coupling.

import Foundation

/// Named environments the companion app can talk to.
enum AppProfile: String, CaseIterable {
    case production
    case staging
    case dev

    /// Mirrors `octomil-ios/Sources/Octomil/Client/Profile.swift`'s
    /// `OctomilProfileResolver.hostURLs`. Keep in lockstep.
    var defaultHostURL: URL {
        switch self {
        case .production:
            return URL(string: "https://api.octomil.com")!
        case .staging:
            return URL(string: "https://api.staging.octomil.com")!
        case .dev:
            return URL(string: "http://localhost:8000")!
        }
    }

    /// Operator-friendly label shown in Settings.
    var displayName: String {
        switch self {
        case .production: return "Production"
        case .staging: return "Staging"
        case .dev: return "Local Dev"
        }
    }

    /// Case-insensitive lookup with `prod`/`stg` aliases.
    static func from(_ raw: String) -> AppProfile? {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let aliases: [String: String] = [
            "prod": "production",
            "stg": "staging",
            "staging-2": "staging",
        ]
        let resolved = aliases[normalized] ?? normalized
        return AppProfile(rawValue: resolved)
    }
}

/// Static helpers for picking the default server URL when the user
/// hasn't configured one explicitly.
enum AppProfileResolver {
    /// Resolution order:
    ///
    ///   1. `OCTOMIL_PROFILE` ProcessInfo env var if set.
    ///   2. `OCTOMIL_API_BASE` / `OCTOMIL_API_URL` host inference.
    ///   3. Default `.production`.
    ///
    /// Note: companion app does not accept an "explicit profile"
    /// argument the way the SDK does — there's no equivalent of an
    /// API constructor caller. Users override the URL via Settings,
    /// not via a profile name. This resolver only picks the
    /// FIRST-RUN default before the user has configured anything.
    static func resolveDefault(environment: [String: String]? = nil) -> AppProfile {
        let env = environment ?? ProcessInfo.processInfo.environment

        let rawEnv = (env["OCTOMIL_PROFILE"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !rawEnv.isEmpty, let p = AppProfile.from(rawEnv) {
            return p
        }

        // Trim BEFORE selecting so a whitespace OCTOMIL_API_BASE
        // doesn't mask a valid OCTOMIL_API_URL (codex post-debate N1).
        let baseTrimmed = (env["OCTOMIL_API_BASE"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let urlTrimmed = (env["OCTOMIL_API_URL"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let url = baseTrimmed.isEmpty ? urlTrimmed : baseTrimmed
        if let p = inferFromURL(url) {
            return p
        }

        return .production
    }

    /// Convenience: the profile-aware default URL string. Used at
    /// runtime by ``AppState.init()`` to flip the persisted
    /// ``serverURL`` from prod → staging when the user hasn't pinned
    /// a custom URL yet. (`@AppStorage` requires a literal default
    /// at compile time, so the runtime-init path is the only place
    /// this value can be applied.)
    static func defaultServerURLString(environment: [String: String]? = nil) -> String {
        resolveDefault(environment: environment).defaultHostURL.absoluteString
    }

    private static func inferFromURL(_ raw: String) -> AppProfile? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // Use URLComponents to parse; substring matching the raw URL
        // would let evil.test/?next=api.staging.octomil.com or
        // api.octomil.com.evil.test spoof a profile and route the
        // app's first-run URL to the wrong env (codex post-debate B1).
        guard
            let components = URLComponents(string: trimmed),
            let host = components.host?.lowercased(),
            !host.isEmpty
        else {
            return nil
        }
        // Exact-host markers — staging FIRST (more specific).
        let markers: [(AppProfile, Set<String>)] = [
            (.staging, ["api.staging.octomil.com"]),
            (.production, ["api.octomil.com"]),
            (.dev, ["localhost", "127.0.0.1", "0.0.0.0"]),
        ]
        for (profile, ms) in markers where ms.contains(host) {
            return profile
        }
        return nil
    }
}
