import Foundation
import Security

struct StoredTokens: Codable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date?
    var email: String?
}

/// Wraps Keychain storage for the Google session.
final class TokenStore {
    private let service = "com.reagan.betterspotlight"
    private let account: String

    init(account: String) { self.account = account }

    func save(_ tokens: StoredTokens) {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  account,
        ]
        SecItemDelete(query as CFDictionary)
        var attrs = query
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(attrs as CFDictionary, nil)
        if status != errSecSuccess { Log.warn("keychain save failed: \(status)") }
    }

    func load() -> StoredTokens? {
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  account,
            kSecReturnData as String:   true,
            kSecMatchLimit as String:   kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(StoredTokens.self, from: data)
    }

    func clear() {
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
