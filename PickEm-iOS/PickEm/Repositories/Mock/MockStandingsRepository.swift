import Foundation

final class MockStandingsRepository: StandingsRepositoryProtocol {
    func fetchStandings(groupID: String) async throws -> [Standing] {
        MockData.standings
            .filter { $0.groupID == groupID }
            .sorted {
                if $0.winPercentage != $1.winPercentage {
                    return $0.winPercentage > $1.winPercentage
                }
                return $0.wins > $1.wins
            }
    }
}
