import Foundation
import SwiftData

/// Single dependency injection root. Change the active compilation condition to
/// swap repository implementations across the whole app:
///   - MOCK_LOCAL    → LocalMockRepository (no network; Phase 1)
///   - MOCK_BACKEND  → Live repos against local FastAPI dev server (Phase 2)
///   - (default)     → Live repos against production API (Phase 4)
@Observable
@MainActor
final class AppDependencies {
    let authRepository: any AuthRepositoryProtocol
    let groupRepository: any GroupRepositoryProtocol
    let gameRepository: any GameRepositoryProtocol
    let pickRepository: any PickRepositoryProtocol
    let standingsRepository: any StandingsRepositoryProtocol
    let tokenStore: TokenStore
    let authViewModel: AuthViewModel
    let groupViewModel: GroupViewModel
    let cacheService: LocalCacheService
    let notificationService: NotificationService

    init() {
        let store = TokenStore()
        self.tokenStore = store

        let schema = Schema([CachedGame.self, CachedPick.self, CachedStanding.self])
        let fallbackConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = (try? ModelContainer(for: schema)) ?? (try! ModelContainer(for: schema, configurations: fallbackConfig))
        let cache = LocalCacheService(container: container)
        self.cacheService = cache

        #if MOCK_LOCAL
        let auth = MockAuthRepository()
        let group = MockGroupRepository()
        let game = MockGameRepository()
        let pick = MockPickRepository()
        let standings = MockStandingsRepository()

        #elseif MOCK_BACKEND
        let devURL = URL(string: ProcessInfo.processInfo.environment["DEV_SERVER_URL"] ?? "http://localhost:8000")!
        let network = NetworkService(baseURL: devURL, tokenStore: store)
        let auth = LiveAuthRepository(network: network)
        let group = LiveGroupRepository(network: network)
        let game = LiveGameRepository(network: network, cache: cache)
        let pick = LivePickRepository(network: network)
        let standings = LiveStandingsRepository(network: network, cache: cache)

        #else
        let apiURL = URL(string: ProcessInfo.processInfo.environment["API_BASE_URL"] ?? "https://pickem-api.fly.dev")!
        let network = NetworkService(baseURL: apiURL, tokenStore: store)
        let auth = LiveAuthRepository(network: network)
        let group = LiveGroupRepository(network: network)
        let game = LiveGameRepository(network: network, cache: cache)
        let pick = LivePickRepository(network: network)
        let standings = LiveStandingsRepository(network: network, cache: cache)
        #endif

        authRepository = auth
        groupRepository = group
        gameRepository = game
        pickRepository = pick
        standingsRepository = standings
        authViewModel = AuthViewModel(authRepository: auth, tokenStore: store)
        groupViewModel = GroupViewModel(groupRepository: group)
        notificationService = NotificationService(authRepository: auth, cacheService: cache)
    }
}
