import Foundation

struct StandingDTO: Codable {
    let userID: String
    let groupID: String
    let displayName: String
    let wins: Int
    let losses: Int
    let superdogWins: Int
    let superdogsUsed: Int
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case wins, losses
        case userID = "user_id"
        case groupID = "group_id"
        case displayName = "display_name"
        case superdogWins = "superdog_wins"
        case superdogsUsed = "superdogs_used"
        case updatedAt = "updated_at"
    }

    func toDomain() -> Standing {
        Standing(
            userID: userID,
            groupID: groupID,
            displayName: displayName,
            wins: wins,
            losses: losses,
            superdogWins: superdogWins,
            superdogsUsed: superdogsUsed,
            updatedAt: updatedAt
        )
    }
}
