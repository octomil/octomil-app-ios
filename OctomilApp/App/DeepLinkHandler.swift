import Foundation

/// Result of parsing an Octomil deep link URL.
struct DeepLinkResult {
    let pairingCode: String
    let host: String?
}

/// Parses deep link URLs for the Octomil pairing flow.
///
/// Supports URLs of the form:
/// ```
/// octomil://pair?token=X&host=Y
/// octomil://pair?code=X&server=Y
/// https://octomil.com/pair?token=X&host=Y
/// ```
///
/// Both `token`/`code` and `host`/`server` parameter names are accepted
/// for backwards compatibility. Universal Links (https://octomil.com/pair)
/// are also supported.
enum DeepLinkHandler {

    /// Parses a deep link URL and returns the pairing info if valid.
    ///
    /// - Parameter url: The deep link URL to parse.
    /// - Returns: A ``DeepLinkResult`` if the URL is a valid pairing deep link, or `nil`.
    static func parse(_ url: URL) -> DeepLinkResult? {
        let isCustomScheme = url.scheme == "octomil" && url.host == "pair"
        let isUniversalLink = url.scheme == "https" && url.host == "octomil.com" && url.path == "/pair"
        guard isCustomScheme || isUniversalLink else { return nil }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let items = components.queryItems ?? []
        // Support both token/code and host/server for backwards compat
        let code = items.first(where: { $0.name == "token" })?.value
            ?? items.first(where: { $0.name == "code" })?.value
        let host = items.first(where: { $0.name == "host" })?.value
            ?? items.first(where: { $0.name == "server" })?.value

        guard let pairingCode = code, !pairingCode.isEmpty else { return nil }

        let resolvedHost: String? = (host?.isEmpty == false) ? host : nil

        return DeepLinkResult(pairingCode: pairingCode, host: resolvedHost)
    }
}
