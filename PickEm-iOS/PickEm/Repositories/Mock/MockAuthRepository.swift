import Foundation

final class MockAuthRepository: AuthRepositoryProtocol {
    func login(email: String, password: String) async throws -> (user: User, accessToken: String, refreshToken: String) {
        (user: MockData.currentUser, accessToken: "mock-access-token", refreshToken: "mock-refresh-token")
    }

    func register(email: String, displayName: String, password: String) async throws -> (user: User, accessToken: String, refreshToken: String) {
        let user = User(id: UUID().uuidString, email: email, displayName: displayName, fcmToken: nil, createdAt: Date())
        return (user: user, accessToken: "mock-access-token", refreshToken: "mock-refresh-token")
    }

    func logout(refreshToken: String) async throws {}

    func refreshAccessToken(refreshToken: String) async throws -> String {
        "mock-access-token-refreshed"
    }

    func updateFCMToken(_ token: String) async throws {}

    func fetchCurrentUser() async throws -> User {
        MockData.currentUser
    }
}
