import Foundation

protocol GameRepositoryProtocol {
    func fetchWeeks(groupID: String) async throws -> [Week]
    func fetchGames(groupID: String, weekID: String) async throws -> [Game]
    func fetchAvailableOdds(sport: Sport, groupID: String?, weekID: String?) async throws -> [Game]
    func createWeek(groupID: String, label: String, startsOn: Date, endsOn: Date?) async throws -> Week
    func addGameToSlate(groupID: String, weekID: String, oddsAPIID: String) async throws -> Game
    func removeGameFromSlate(groupID: String, weekID: String, gameID: String) async throws
    func populateSlate(groupID: String) async throws -> [Week]
}
