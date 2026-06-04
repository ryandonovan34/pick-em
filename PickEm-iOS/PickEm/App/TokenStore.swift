import Foundation

/// Simple in-memory token store for Phase 1. Phase 4 should migrate to Keychain.
final class TokenStore {
    private(set) var accessToken: String?
    private(set) var refreshToken: String?

    func save(accessToken: String, refreshToken: String) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
    }

    func clear() {
        accessToken = nil
        refreshToken = nil
    }
}
