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

    var totalGames: Int { wins + losses }

    var winPercentage: Double {
        guard totalGames > 0 else { return 0 }
        return Double(wins) / Double(totalGames)
    }

    var record: String { "\(wins)-\(losses)" }
}
