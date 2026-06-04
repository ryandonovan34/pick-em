import Foundation

@Observable
@MainActor
final class StandingsViewModel {
    var standings: [Standing] = []
    var isLoading = false
    var errorMessage: String?

    private let standingsRepository: any StandingsRepositoryProtocol
    private let cacheService: LocalCacheService?
    let group: Group

    init(group: Group, standingsRepository: any StandingsRepositoryProtocol, cacheService: LocalCacheService? = nil) {
        self.group = group
        self.standingsRepository = standingsRepository
        self.cacheService = cacheService
    }

    func loadStandings() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            standings = try await standingsRepository.fetchStandings(groupID: group.id)
        } catch {
            errorMessage = "Failed to fetch standings: \(error.localizedDescription)"
        }
    }

    func refresh() async {
        cacheService?.invalidate(scope: .standings(groupID: group.id))
        await loadStandings()
    }
}
