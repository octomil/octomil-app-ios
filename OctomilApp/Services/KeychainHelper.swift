import Foundation
import os.log
import Security

/// Minimal Keychain wrapper for persisting credentials across app reinstalls.
///
/// iOS Keychain items survive app deletion and reinstall, unlike UserDefaults.
/// This is used to preserve device token, org ID, and server URL so that
/// model auto-recovery can work after a reinstall.
enum KeychainHelper {

    private static let service = "ai.octomil.app"
    private static let logger = Logger(subsystem: "ai.octomil.app", category: "Keychain")

    @discardableResult
    static func save(key: String, value: String) -> Bool {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
        ]
        let attributes: [CFString: Any] = [
            kSecValueData: Data(value.utf8),
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { $1 } as CFDictionary, nil)
        }
        if status != errSecSuccess {
            logger.error("Keychain save failed for \(key, privacy: .public): \(status)")
        }
        return status == errSecSuccess
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
