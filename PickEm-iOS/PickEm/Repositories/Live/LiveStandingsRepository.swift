import Foundation

final class LiveStandingsRepository: StandingsRepositoryProtocol {
    private let network: NetworkService
    private let cache: LocalCacheService

    init(network: NetworkService, cache: LocalCacheService) {
        self.network = network
        self.cache = cache
    }

    func fetchStandings(groupID: String) async throws -> [Standing] {
        if let cached = await MainActor.run(body: { cache.loadStandings(groupID: groupID) }), !cached.isEmpty {
            return cached
        }
        let dtos: [StandingDTO] = try await network.get("/groups/\(groupID)/standings")
        let standings = dtos.map { $0.toDomain() }
        await MainActor.run { cache.saveStandings(standings, groupID: groupID) }
        return standings
    }
}
