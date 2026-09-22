import Foundation

struct Standing: Identifiable, Equatable, Hashable, Codable {
    let userID: String
    let groupID: String
    let displayName: String
    let wins: Int
    let losses: Int
    let superdogWins: Int
    let superdogsUsed: Int
    let updatedAt: Date

    var id: String { "\(userID)-\(groupID)" }

    /// A superdog win counts as 3 regular wins — matches the backend's
    /// StandingRead.win_percentage/record computation
    /// (pickem-api/app/schemas/standing.py) and the same weighting
    /// PlayerHistoryRow already used for its own running record.
    var effectiveWins: Int { wins + superdogWins * 3 }

    var totalGames: Int { effectiveWins + losses }

    var winPercentage: Double {
        guard totalGames > 0 else { return 0 }
        return Double(effectiveWins) / Double(totalGames)
    }

    var record: String { "\(effectiveWins)-\(losses)" }
}
