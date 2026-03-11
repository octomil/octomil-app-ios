import Foundation
import Testing
@testable import OctomilAppLib

@Suite("DeepLinkHandler")
struct DeepLinkHandlerTests {

    // MARK: - Valid URLs

    @Test("Parses valid deep link with token and host")
    func parseValidDeepLinkWithTokenAndHost() {
        let url = URL(string: "octomil://pair?token=ABC123&host=https://api.octomil.com")!
        let result = DeepLinkHandler.parse(url)

        #expect(result != nil)
        #expect(result?.pairingCode == "ABC123")
        #expect(result?.host == "https://api.octomil.com")
    }

    @Test("Parses valid deep link with code and server (backwards compat)")
    func parseValidDeepLinkWithCodeAndServer() {
        let url = URL(string: "octomil://pair?code=XYZ789&server=https://staging.octomil.com")!
        let result = DeepLinkHandler.parse(url)

        #expect(result != nil)
        #expect(result?.pairingCode == "XYZ789")
        #expect(result?.host == "https://staging.octomil.com")
    }

    @Test("Token takes precedence over code when both present")
    func parseTokenTakesPrecedenceOverCode() {
        let url = URL(string: "octomil://pair?token=PRIMARY&code=SECONDARY")!
        let result = DeepLinkHandler.parse(url)

        #expect(result != nil)
        #expect(result?.pairingCode == "PRIMARY")
    }

    @Test("Host takes precedence over server when both present")
    func parseHostTakesPrecedenceOverServer() {
        let url = URL(string: "octomil://pair?token=T&host=PRIMARY&server=SECONDARY")!
        let result = DeepLinkHandler.parse(url)

        #expect(result?.host == "PRIMARY")
    }

    @Test("Parses deep link with token only (no host)")
    func parseWithTokenOnly() {
        let url = URL(string: "octomil://pair?token=NOHOST")!
        let result = DeepLinkHandler.parse(url)

        #expect(result != nil)
        #expect(result?.pairingCode == "NOHOST")
        #expect(result?.host == nil)
    }

    // MARK: - Invalid URLs

    @Test("Rejects wrong scheme")
    func parseRejectsWrongScheme() {
        let url = URL(string: "https://pair?token=ABC123")!
        let result = DeepLinkHandler.parse(url)

        #expect(result == nil)
    }

    @Test("Rejects wrong host")
    func parseRejectsWrongHost() {
        let url = URL(string: "octomil://settings?token=ABC123")!
        let result = DeepLinkHandler.parse(url)

        #expect(result == nil)
    }

    @Test("Rejects missing token")
    func parseRejectsMissingToken() {
        let url = URL(string: "octomil://pair?host=https://api.octomil.com")!
        let result = DeepLinkHandler.parse(url)

        #expect(result == nil)
    }

    @Test("Rejects empty token")
    func parseRejectsEmptyToken() {
        let url = URL(string: "octomil://pair?token=")!
        let result = DeepLinkHandler.parse(url)

        #expect(result == nil)
    }

    @Test("Rejects URL with no query params")
    func parseRejectsNoQueryParams() {
        let url = URL(string: "octomil://pair")!
        let result = DeepLinkHandler.parse(url)

        #expect(result == nil)
    }

    // MARK: - Universal Links

    @Test("Parses Universal Link with token and host")
    func parseUniversalLinkWithTokenAndHost() {
        let url = URL(string: "https://octomil.com/pair?token=ABC123&host=https://api.octomil.com")!
        let result = DeepLinkHandler.parse(url)

        #expect(result != nil)
        #expect(result?.pairingCode == "ABC123")
        #expect(result?.host == "https://api.octomil.com")
    }

    @Test("Parses Universal Link with code and server (backwards compat)")
    func parseUniversalLinkWithCodeAndServer() {
        let url = URL(string: "https://octomil.com/pair?code=XYZ&server=https://staging.octomil.com")!
        let result = DeepLinkHandler.parse(url)

        #expect(result != nil)
        #expect(result?.pairingCode == "XYZ")
        #expect(result?.host == "https://staging.octomil.com")
    }

    @Test("Rejects Universal Link with wrong host")
    func parseRejectsUniversalLinkWrongHost() {
        let url = URL(string: "https://other.com/pair?token=ABC")!
        let result = DeepLinkHandler.parse(url)

        #expect(result == nil)
    }

    // MARK: - Edge Cases

    @Test("Treats empty host as nil")
    func parseWithEmptyHost() {
        let url = URL(string: "octomil://pair?token=T&host=")!
        let result = DeepLinkHandler.parse(url)

        #expect(result != nil)
        #expect(result?.pairingCode == "T")
        #expect(result?.host == nil)
    }

    @Test("Handles special characters in token")
    func parseWithSpecialCharactersInToken() {
        let url = URL(string: "octomil://pair?token=abc-123_XYZ.456")!
        let result = DeepLinkHandler.parse(url)

        #expect(result != nil)
        #expect(result?.pairingCode == "abc-123_XYZ.456")
    }

    @Test("Handles URL-encoded host")
    func parseWithURLEncodedHost() {
        let url = URL(string: "octomil://pair?token=T&host=https%3A%2F%2Fapi.octomil.com%2Fapi%2Fv1")!
        let result = DeepLinkHandler.parse(url)

        #expect(result != nil)
        #expect(result?.host == "https://api.octomil.com/api/v1")
    }

    @Test("Ignores unknown query parameters")
    func parseWithExtraQueryParameters() {
        let url = URL(string: "octomil://pair?token=T&host=H&model=phi-4-mini&extra=ignored")!
        let result = DeepLinkHandler.parse(url)

        #expect(result != nil)
        #expect(result?.pairingCode == "T")
        #expect(result?.host == "H")
    }
}
