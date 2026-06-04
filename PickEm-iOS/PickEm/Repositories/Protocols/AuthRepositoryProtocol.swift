import Foundation

protocol AuthRepositoryProtocol {
    func login(email: String, password: String) async throws -> (user: User, accessToken: String, refreshToken: String)
    func register(email: String, displayName: String, password: String) async throws -> (user: User, accessToken: String, refreshToken: String)
    func logout() async throws
    func refreshAccessToken(refreshToken: String) async throws -> String
    func updateFCMToken(_ token: String) async throws
}
