import Foundation

final class LiveStandingsRepository: StandingsRepositoryProtocol {
    private let network: NetworkService
    private let cache: LocalCacheService

    init(network: NetworkService, cache: LocalCacheService) {
        self.network = network
        self.cache = cache
    }

    func fetchStandings(groupID: String) async throws -> [Standing] {
        // Network-first: standings change the moment results are graded, and
        // hitting our own backend costs nothing against the Odds API's free
        // tier (that's a separate, server-side concern — see
        // ODDS_CACHE_TTL_MINUTES), so there's no reason to prefer a
        // potentially-stale local copy over a live one. The cache is purely
        // an offline fallback now, not a way to avoid the round trip.
        do {
            let dtos: [StandingDTO] = try await network.get("/groups/\(groupID)/standings")
            let standings = dtos.map { $0.toDomain() }
            await MainActor.run { cache.saveStandings(standings, groupID: groupID) }
            return standings
        } catch {
            if let cached = await MainActor.run(body: { cache.loadStandings(groupID: groupID) }), !cached.isEmpty {
                return cached
            }
            throw error
        }
    }
}
