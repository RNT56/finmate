import Foundation
import Supabase
import Security

// MARK: - Keychain-backed auth token storage (docs/07 §3)
//
// supabase-swift persists the logged-in session through an `AuthLocalStorage`.
// Per the golden rules, auth tokens MUST live in the Keychain — never
// `UserDefaults`. This is a small, dependency-free `SecItem` wrapper scoped to a
// single service so every Finmate build shares one keychain namespace.
//
// The SDK ships a `KeychainLocalStorage` of its own; we provide an explicit
// implementation so the storage contract (and its accessibility class) is owned
// by Finmate and auditable against docs/07.

/// `AuthLocalStorage` over the iOS/macOS Keychain (Security framework).
/// Items are stored with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` so
/// tokens survive backgrounding but never leave the device or sync to iCloud.
public struct KeychainAuthStorage: AuthLocalStorage {
    private let service: String
    private let accessGroup: String?

    public init(service: String = "app.finmate.auth", accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }

    public func store(key: String, value: Data) throws {
        var query = baseQuery(key: key)
        // Upsert: delete any existing item, then add fresh.
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = value
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unhandled(status) }
    }

    public func retrieve(key: String) throws -> Data? {
        var query = baseQuery(key: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess: return result as? Data
        case errSecItemNotFound: return nil
        default: throw KeychainError.unhandled(status)
        }
    }

    public func remove(key: String) throws {
        let status = SecItemDelete(baseQuery(key: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandled(status)
        }
    }

    private func baseQuery(key: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        return query
    }
}

public enum KeychainError: Error, Sendable {
    case unhandled(OSStatus)
}
