import Foundation
import Security
import Observation

@Observable
final class TokenStore {
    private enum Key {
        static let accessToken  = "com.pickem.accessToken"
        static let refreshToken = "com.pickem.refreshToken"
    }

    private(set) var accessToken: String?  = Keychain.read(Key.accessToken)
    private(set) var refreshToken: String? = Keychain.read(Key.refreshToken)

    func save(accessToken: String, refreshToken: String) {
        self.accessToken  = accessToken
        self.refreshToken = refreshToken
        Keychain.write(accessToken,  key: Key.accessToken)
        Keychain.write(refreshToken, key: Key.refreshToken)
    }

    func saveAccessToken(_ token: String) {
        accessToken = token
        Keychain.write(token, key: Key.accessToken)
    }

    func clear() {
        accessToken  = nil
        refreshToken = nil
        Keychain.delete(Key.accessToken)
        Keychain.delete(Key.refreshToken)
    }
}

private enum Keychain {
    static func write(_ value: String, key: String) {
        let data = Data(value.utf8)
        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrAccount:      key,
            kSecValueData:        data,
            kSecAttrAccessible:   kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func read(_ key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecReturnData:  kCFBooleanTrue!,
            kSecMatchLimit:  kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrAccount: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
