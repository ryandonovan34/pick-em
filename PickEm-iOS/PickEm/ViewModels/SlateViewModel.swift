import Foundation

@Observable
@MainActor
final class SlateViewModel {
    var weeks: [Week] = []
    var games: [Game] = []
    var availableGames: [Game] = []
    var selectedWeek: Week?
    var isLoading = false
    var isPopulating = false
    var errorMessage: String?

    private let gameRepository: any GameRepositoryProtocol
    private let cacheService: LocalCacheService?
    let group: Group
    var currentUserID: String

    var isAdmin: Bool { group.adminID == currentUserID }

    init(group: Group, gameRepository: any GameRepositoryProtocol, cacheService: LocalCacheService? = nil, currentUserID: String = "") {
        self.group = group
        self.gameRepository = gameRepository
        self.cacheService = cacheService
        self.currentUserID = currentUserID
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

    // MARK: - Admin slate management

    func populate() async {
        isPopulating = true
        defer { isPopulating = false }
        do {
            let newWeeks = try await gameRepository.populateSlate(groupID: group.id)
            if !newWeeks.isEmpty {
                await loadWeeks()
            }
        } catch {
            errorMessage = "Failed to populate slate: \(error.localizedDescription)"
        }
    }

    func createWeek(label: String) async throws -> Week {
        let week = try await gameRepository.createWeek(groupID: group.id, label: label)
        weeks.append(week)
        weeks.sort { $0.weekNumber < $1.weekNumber }
        selectedWeek = week
        games = []
        return week
    }

    func fetchAvailableOdds() async {
        do {
            availableGames = try await gameRepository.fetchAvailableOdds(sport: group.sport, groupID: group.id)
        } catch {
            availableGames = []
        }
    }

    func addGame(_ game: Game, to week: Week) async throws {
        guard let oddsAPIID = game.oddsAPIID else { return }
        let added = try await gameRepository.addGameToSlate(groupID: group.id, weekID: week.id, oddsAPIID: oddsAPIID)
        if week.id == selectedWeek?.id {
            games.append(added)
            games.sort { $0.kickoffAt < $1.kickoffAt }
        }
        availableGames.removeAll { $0.id == game.id }
    }

    func removeGame(_ game: Game, from week: Week) async throws {
        try await gameRepository.removeGameFromSlate(groupID: group.id, weekID: week.id, gameID: game.id)
        if week.id == selectedWeek?.id {
            games.removeAll { $0.id == game.id }
        }
        availableGames.append(game)
        availableGames.sort { $0.kickoffAt < $1.kickoffAt }
    }
}
