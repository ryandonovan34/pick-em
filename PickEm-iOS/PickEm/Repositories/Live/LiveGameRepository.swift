import Foundation

final class LiveGameRepository: GameRepositoryProtocol {
    private let network: NetworkService
    private let cache: LocalCacheService

    init(network: NetworkService, cache: LocalCacheService) {
        self.network = network
        self.cache = cache
    }

    func fetchWeeks(groupID: String) async throws -> [Week] {
        let dtos: [WeekDTO] = try await network.get("/groups/\(groupID)/weeks")
        return dtos.map { $0.toDomain() }
    }

    func fetchGames(groupID: String, weekID: String) async throws -> [Game] {
        let cacheKey = "games:\(weekID)"
        if let cached = await MainActor.run(body: { cache.loadGames(groupID: groupID, weekID: weekID) }) {
            NetworkLogger.logCache(hit: true, for: cacheKey)
            return cached
        }
        NetworkLogger.logCache(hit: false, for: cacheKey)
        let dtos: [GameDTO] = try await network.get("/groups/\(groupID)/weeks/\(weekID)/games")
        let games = dtos.map { $0.toDomain() }
        await MainActor.run { cache.saveGames(games, groupID: groupID, weekID: weekID) }
        return games
    }

    func fetchAvailableOdds(sport: Sport, groupID: String?) async throws -> [Game] {
        var path = "/odds/available?sport=\(sport.rawValue)"
        if let groupID {
            path += "&group_id=\(groupID)"
        }
        let dtos: [GameDTO] = try await network.get(path)
        return dtos.map { $0.toDomain() }
    }

    func populateSlate(groupID: String) async throws -> [Week] {
        struct Empty: Encodable {}
        let dtos: [WeekDTO] = try await network.post("/groups/\(groupID)/populate", body: Empty())
        return dtos.map { $0.toDomain() }
    }

    func createWeek(groupID: String, label: String) async throws -> Week {
        struct CreateWeekBody: Encodable { let label: String }
        let dto: WeekDTO = try await network.post("/groups/\(groupID)/weeks", body: CreateWeekBody(label: label))
        return dto.toDomain()
    }

    func addGameToSlate(groupID: String, weekID: String, oddsAPIID: String) async throws -> Game {
        struct AddGameBody: Encodable { let odds_api_id: String }
        let dto: GameDTO = try await network.post("/groups/\(groupID)/weeks/\(weekID)/games", body: AddGameBody(odds_api_id: oddsAPIID))
        // Admin slate changes invalidate the cached games for this week
        await MainActor.run { cache.invalidate(scope: .slate(groupID: groupID, weekID: weekID)) }
        return dto.toDomain()
    }

    func removeGameFromSlate(groupID: String, weekID: String, gameID: String) async throws {
        try await network.delete("/groups/\(groupID)/weeks/\(weekID)/games/\(gameID)")
        await MainActor.run { cache.invalidate(scope: .slate(groupID: groupID, weekID: weekID)) }
    }
}
