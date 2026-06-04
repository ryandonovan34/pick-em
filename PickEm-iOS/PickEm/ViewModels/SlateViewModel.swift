import Foundation

@Observable
@MainActor
final class SlateViewModel {
    var weeks: [Week] = []
    var games: [Game] = []
    var selectedWeek: Week?
    var isLoading = false
    var errorMessage: String?

    private let gameRepository: any GameRepositoryProtocol
    private let cacheService: LocalCacheService?
    let group: Group

    init(group: Group, gameRepository: any GameRepositoryProtocol, cacheService: LocalCacheService? = nil) {
        self.group = group
        self.gameRepository = gameRepository
        self.cacheService = cacheService
    }

    func loadWeeks() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            weeks = try await gameRepository.fetchWeeks(groupID: group.id)
            if selectedWeek == nil {
                selectedWeek = weeks.last
            }
            if let week = selectedWeek {
                await loadGames(for: week)
            }
        } catch {
            errorMessage = "Failed to fetch weeks: \(error.localizedDescription)"
        }
    }

    func selectWeek(_ week: Week) async {
        selectedWeek = week
        await loadGames(for: week)
    }

    func loadGames(for week: Week) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            games = try await gameRepository.fetchGames(groupID: group.id, weekID: week.id)
        } catch {
            errorMessage = "Failed to fetch games: \(error.localizedDescription)"
        }
    }

    func refresh() async {
        guard let week = selectedWeek else { return }
        cacheService?.invalidate(scope: .slate(groupID: group.id, weekID: week.id))
        await loadGames(for: week)
    }
}
