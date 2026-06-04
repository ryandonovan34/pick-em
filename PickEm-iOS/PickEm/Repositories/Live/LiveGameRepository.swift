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
        if let cached = await MainActor.run(body: { cache.loadGames(groupID: groupID, weekID: weekID) }) {
            return cached
        }
        let dtos: [GameDTO] = try await network.get("/groups/\(groupID)/weeks/\(weekID)/games")
        let games = dtos.map { $0.toDomain() }
        await MainActor.run { cache.saveGames(games, groupID: groupID, weekID: weekID) }
        return games
    }

    func fetchAvailableOdds(sport: Sport, dateRange: ClosedRange<Date>?) async throws -> [Game] {
        var path = "/odds/available?sport=\(sport.rawValue)"
        let fmt = ISO8601DateFormatter()
        if let range = dateRange {
            path += "&date_from=\(fmt.string(from: range.lowerBound))&date_to=\(fmt.string(from: range.upperBound))"
        }
        let dtos: [GameDTO] = try await network.get(path)
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
