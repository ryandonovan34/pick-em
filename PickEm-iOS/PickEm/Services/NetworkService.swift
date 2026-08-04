import Foundation

final class NetworkService {
    private let baseURL: URL
    private let tokenStore: TokenStore
    private let session: URLSession

    init(baseURL: URL, tokenStore: TokenStore, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.tokenStore = tokenStore
        self.session = session
    }

    func get<T: Decodable>(_ path: String) async throws -> T {
        let request = try buildRequest(method: "GET", path: path, body: nil as String?)
        return try await perform(request)
    }

    func post<B: Encodable, T: Decodable>(_ path: String, body: B) async throws -> T {
        let request = try buildRequest(method: "POST", path: path, body: body)
        return try await perform(request)
    }

    @discardableResult
    func put<B: Encodable, T: Decodable>(_ path: String, body: B) async throws -> T {
        let request = try buildRequest(method: "PUT", path: path, body: body)
        return try await perform(request)
    }

    func put<B: Encodable>(_ path: String, body: B) async throws {
        let request = try buildRequest(method: "PUT", path: path, body: body)
        let _: EmptyResponse = try await perform(request)
    }

    func delete(_ path: String) async throws {
        let request = try buildRequest(method: "DELETE", path: path, body: nil as String?)
        let _: EmptyResponse = try await perform(request)
    }

    private func buildRequest<B: Encodable>(method: String, path: String, body: B?) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw RepositoryError.unknown
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = tokenStore.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
        }
        return request
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        NetworkLogger.logRequest(request)
        let start = Date()
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw RepositoryError.unknown }
        NetworkLogger.logResponse(http, data: data, duration: Date().timeIntervalSince(start), for: request)

        // On 401, try a token refresh and retry the original request once.
        if http.statusCode == 401 {
            if let newToken = try? await refreshAccessToken() {
                // Dispatch to main actor so @Observable TokenStore mutations
                // trigger SwiftUI re-renders on the correct thread.
                await MainActor.run { tokenStore.saveAccessToken(newToken) }
                var retried = request
                retried.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                let (data2, response2) = try await session.data(for: retried)
                guard let http2 = response2 as? HTTPURLResponse else { throw RepositoryError.unknown }
                return try decode(http2, data: data2)
            } else if tokenStore.accessToken != nil {
                // Had a session but both the access and refresh tokens are invalid — clear to force re-login.
                await MainActor.run { tokenStore.clear() }
            }
        }

        return try decode(http, data: data)
    }

    private func decode<T: Decodable>(_ http: HTTPURLResponse, data: Data) throws -> T {
        switch http.statusCode {
        case 200...299:
            let decodableData = data.isEmpty ? Data("{}".utf8) : data
            do {
                return try Self.decoder.decode(T.self, from: decodableData)
            } catch {
                throw RepositoryError.decodingError(error)
            }
        case 401:
            throw RepositoryError.unauthorized
        case 403:
            let msg = APIError.extract(from: data) ?? "You don't have permission to do this."
            throw RepositoryError.forbidden(msg)
        case 404:
            throw RepositoryError.notFound
        case 409:
            let msg = (try? JSONDecoder().decode(APIError.self, from: data))?.detail ?? "Conflict"
            throw RepositoryError.conflict(msg)
        default:
            let msg = APIError.extract(from: data) ?? "Unknown"
            throw RepositoryError.serverError(http.statusCode, msg)
        }
    }

    private func refreshAccessToken() async throws -> String {
        guard let refreshToken = tokenStore.refreshToken else { throw RepositoryError.unauthorized }
        struct Body: Encodable { let refresh_token: String }
        struct Response: Decodable { let access_token: String }
        let req = try buildRequest(method: "POST", path: "auth/refresh", body: Body(refresh_token: refreshToken))
        let (data, _) = try await session.data(for: req)
        return try JSONDecoder().decode(Response.self, from: data).access_token
    }
}

private extension NetworkService {
    static let decoder: JSONDecoder = {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let withoutFraction = ISO8601DateFormatter()
        withoutFraction.formatOptions = [.withInternetDateTime]

        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = withFraction.date(from: string) { return date }
            if let date = withoutFraction.date(from: string) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot parse date: \(string)")
        }
        return d
    }()
}

private struct APIError: Decodable {
    let detail: String

    static func extract(from data: Data) -> String? {
        if let simple = try? JSONDecoder().decode(APIError.self, from: data) {
            return simple.detail
        }
        struct ValidationError: Decodable { let msg: String }
        struct ValidationResponse: Decodable { let detail: [ValidationError] }
        if let validation = try? JSONDecoder().decode(ValidationResponse.self, from: data) {
            return validation.detail.map(\.msg).joined(separator: "; ")
        }
        return nil
    }
}

private struct EmptyResponse: Decodable {}
