import Foundation

protocol StandingsRepositoryProtocol {
    func fetchStandings(groupID: String) async throws -> [Standing]
}
