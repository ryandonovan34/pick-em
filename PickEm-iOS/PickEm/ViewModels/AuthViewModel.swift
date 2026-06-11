import Foundation

@Observable
@MainActor
final class AuthViewModel {
    var currentUser: User?
    var isLoading = false
    var loginErrorMessage: String?
    var registerErrorMessage: String?
    var isAuthenticated: Bool { tokenStore.accessToken != nil }

    private let authRepository: any AuthRepositoryProtocol
    private let tokenStore: TokenStore

    init(authRepository: any AuthRepositoryProtocol, tokenStore: TokenStore) {
        self.authRepository = authRepository
        self.tokenStore = tokenStore
    }

    func login(email: String, password: String) async {
        isLoading = true
        loginErrorMessage = nil
        defer { isLoading = false }
        do {
            let result = try await authRepository.login(email: email, password: password)
            tokenStore.save(accessToken: result.accessToken, refreshToken: result.refreshToken)
            currentUser = result.user
        } catch {
            loginErrorMessage = errorMessage(from: error)
        }
    }

    func register(email: String, displayName: String, password: String) async {
        isLoading = true
        registerErrorMessage = nil
        defer { isLoading = false }
        do {
            let result = try await authRepository.register(email: email, displayName: displayName, password: password)
            tokenStore.save(accessToken: result.accessToken, refreshToken: result.refreshToken)
            currentUser = result.user
        } catch {
            registerErrorMessage = errorMessage(from: error)
        }
    }

    func fetchCurrentUser() async {
        guard currentUser == nil else { return }
        do {
            currentUser = try await authRepository.fetchCurrentUser()
        } catch {
            // Non-fatal — user will just lack admin controls until next login
        }
    }

    func logout() async {
        if let refreshToken = tokenStore.refreshToken {
            do { try await authRepository.logout(refreshToken: refreshToken) } catch {}
        }
        tokenStore.clear()
        currentUser = nil
    }

    func errorMessage(from error: Error) -> String {
        guard let repositoryError = error as? RepositoryError else {
            return "Something went wrong"
        }
        switch repositoryError {
        case .unauthorized: return "Invalid email or password"
        case .conflict: return "Email is already taken"
        default: return "Something went wrong"
        }
    }
}
