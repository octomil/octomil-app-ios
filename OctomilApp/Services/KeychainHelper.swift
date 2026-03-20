import Foundation
import Security

/// Minimal Keychain wrapper for persisting credentials across app reinstalls.
///
/// iOS Keychain items survive app deletion and reinstall, unlike UserDefaults.
/// This is used to preserve device token, org ID, and server URL so that
/// model auto-recovery can work after a reinstall.
enum KeychainHelper {

    private static let service = "ai.octomil.app"

    static func save(key: String, value: String) {
        let data = Data(value.utf8)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
        ]
        // Delete any existing item first
        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData] = data
        addQuery[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    static func read(key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(key: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
