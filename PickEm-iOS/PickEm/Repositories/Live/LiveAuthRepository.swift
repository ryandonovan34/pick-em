import Foundation

final class LiveAuthRepository: AuthRepositoryProtocol {
    private let network: NetworkService

    init(network: NetworkService) {
        self.network = network
    }

    func login(email: String, password: String) async throws -> (user: User, accessToken: String, refreshToken: String) {
        let body = ["email": email, "password": password]
        let response: AuthResponseDTO = try await network.post("/auth/login", body: body)
        return (user: response.user.toDomain(), accessToken: response.accessToken, refreshToken: response.refreshToken)
    }

    func register(email: String, displayName: String, password: String) async throws -> (user: User, accessToken: String, refreshToken: String) {
        let body: [String: String] = ["email": email, "display_name": displayName, "password": password]
        let response: AuthResponseDTO = try await network.post("/auth/register", body: body)
        return (user: response.user.toDomain(), accessToken: response.accessToken, refreshToken: response.refreshToken)
    }

    func logout(refreshToken: String) async throws {
        struct LogoutBody: Encodable { let refresh_token: String }
        let _: EmptyResponseBody = try await network.post("/auth/logout", body: LogoutBody(refresh_token: refreshToken))
    }

    func refreshAccessToken(refreshToken: String) async throws -> String {
        struct RefreshRequest: Encodable { let refresh_token: String }
        struct RefreshResponse: Decodable { let access_token: String }
        let response: RefreshResponse = try await network.post("/auth/refresh", body: RefreshRequest(refresh_token: refreshToken))
        return response.access_token
    }

    func updateFCMToken(_ token: String) async throws {
        struct FCMBody: Encodable { let fcm_token: String }
        try await network.put("/auth/fcm-token", body: FCMBody(fcm_token: token))
    }

    func fetchCurrentUser() async throws -> User {
        let dto: UserDTO = try await network.get("/auth/me")
        return dto.toDomain()
    }
}

private struct EmptyBody: Encodable {}
private struct EmptyResponseBody: Decodable {}
