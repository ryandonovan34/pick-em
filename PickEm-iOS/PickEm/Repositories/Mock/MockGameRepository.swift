import Foundation

final class MockGameRepository: GameRepositoryProtocol {
    private var weeks: [Week] = MockData.allWeeks
    private var games: [Game] = MockData.games

    func fetchWeeks(groupID: String) async throws -> [Week] {
        weeks.filter { $0.groupID == groupID }
    }

    func fetchGames(groupID: String, weekID: String) async throws -> [Game] {
        games.filter { $0.weekID == weekID }
    }

    func fetchAvailableOdds(sport: Sport, groupID: String?, weekID: String?) async throws -> [Game] {
        games.filter { $0.sport == sport }
    }

    func populateSlate(groupID: String) async throws -> [Week] {
        weeks.filter { $0.groupID == groupID }
    }

    func createWeek(groupID: String, label: String, startsOn: Date, endsOn: Date?) async throws -> Week {
        let week = Week(
            id: UUID().uuidString,
            groupID: groupID,
            weekNumber: (weeks.map(\.weekNumber).max() ?? 0) + 1,
            label: label,
            createdAt: Date(),
            startsOn: startsOn,
            endsOn: endsOn
        )
        weeks.append(week)
        return week
    }

    func addGameToSlate(groupID: String, weekID: String, oddsAPIID: String) async throws -> Game {
        guard let game = games.first(where: { $0.oddsAPIID == oddsAPIID }) else {
            throw RepositoryError.notFound
        }
        return game
    }

    func removeGameFromSlate(groupID: String, weekID: String, gameID: String) async throws {
        games.removeAll { $0.id == gameID }
    }
}
