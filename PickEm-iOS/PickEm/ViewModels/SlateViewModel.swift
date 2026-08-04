import Foundation

struct WeekGames: Identifiable {
    let week: Week
    var games: [Game]
    var id: String { week.id }

    var allLocked: Bool {
        !games.isEmpty && games.allSatisfy { $0.isLocked }
    }
    var someLocked: Bool {
        games.contains { $0.isLocked }
    }
}

@Observable
@MainActor
final class SlateViewModel {
    var weekGames: [WeekGames] = []
    var availableGames: [Game] = []
    var selectedWeek: Week?
    var isLoading = false
    var isPopulating = false
    var errorMessage: String?

    private let gameRepository: any GameRepositoryProtocol
    private let cacheService: LocalCacheService?
    let group: Group
    var currentUserID: String

    // Backward-compat for SlateManageView which reads `viewModel.weeks` and `viewModel.games`
    var weeks: [Week] { weekGames.map(\.week) }
    var games: [Game] { weekGames.first { $0.week.id == selectedWeek?.id }?.games ?? [] }

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
            let fetchedWeeks = try await gameRepository.fetchWeeks(groupID: group.id)
            var loaded: [WeekGames] = []
            for week in fetchedWeeks {
                let weekGames = (try? await gameRepository.fetchGames(groupID: group.id, weekID: week.id)) ?? []
                loaded.append(WeekGames(week: week, games: weekGames.sorted { $0.kickoffAt < $1.kickoffAt }))
            }
            weekGames = loaded.sorted { $0.week.weekNumber < $1.week.weekNumber }

            let selectedStillExists = fetchedWeeks.contains { $0.id == selectedWeek?.id }
            if selectedWeek == nil || !selectedStillExists {
                selectedWeek = Self.mostRelevantWeek(from: fetchedWeeks)
            }
        } catch {
            errorMessage = "Failed to fetch weeks: \(error.localizedDescription)"
        }
    }

    func selectWeek(_ week: Week) async {
        selectedWeek = week
    }

    func refresh() async {
        for wg in weekGames {
            cacheService?.invalidate(scope: .slate(groupID: group.id, weekID: wg.week.id))
        }
        await loadWeeks()
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

    func createWeek(label: String, startsOn: Date, endsOn: Date? = nil) async throws -> Week {
        let week = try await gameRepository.createWeek(groupID: group.id, label: label, startsOn: startsOn, endsOn: endsOn)
        weekGames.append(WeekGames(week: week, games: []))
        weekGames.sort { $0.week.weekNumber < $1.week.weekNumber }
        selectedWeek = week
        return week
    }

    func fetchAvailableOdds(for week: Week) async {
        do {
            availableGames = try await gameRepository.fetchAvailableOdds(sport: group.sport, groupID: group.id, weekID: week.id)
        } catch {
            availableGames = []
        }
    }

    func addGame(_ game: Game, to week: Week) async throws {
        guard let oddsAPIID = game.oddsAPIID else { return }
        let added = try await gameRepository.addGameToSlate(groupID: group.id, weekID: week.id, oddsAPIID: oddsAPIID)
        if let idx = weekGames.firstIndex(where: { $0.week.id == week.id }) {
            weekGames[idx].games.append(added)
            weekGames[idx].games.sort { $0.kickoffAt < $1.kickoffAt }
        }
        availableGames.removeAll { $0.id == game.id }
    }

    func removeGame(_ game: Game, from week: Week) async throws {
        try await gameRepository.removeGameFromSlate(groupID: group.id, weekID: week.id, gameID: game.id)
        if let idx = weekGames.firstIndex(where: { $0.week.id == week.id }) {
            weekGames[idx].games.removeAll { $0.id == game.id }
        }
        availableGames.append(game)
        availableGames.sort { $0.kickoffAt < $1.kickoffAt }
    }

    // Pick the most contextually relevant week:
    // 1. Active weeks (started but not finished), earliest first
    // 2. Upcoming weeks (not started yet), earliest first
    // 3. Completed weeks (all done), latest as fallback
    private static func mostRelevantWeek(from weeks: [Week]) -> Week? {
        guard !weeks.isEmpty else { return nil }
        if let active = weeks.filter({ $0.isActive }).min(by: { ($0.firstKickoffAt ?? .distantFuture) < ($1.firstKickoffAt ?? .distantFuture) }) {
            return active
        }
        if let upcoming = weeks.filter({ $0.isUpcoming }).min(by: { ($0.firstKickoffAt ?? .distantFuture) < ($1.firstKickoffAt ?? .distantFuture) }) {
            return upcoming
        }
        return weeks.last
    }
}
