import Foundation

struct PickDTO: Codable {
    let id: String
    let userID: String
    let gameID: String
    let groupID: String
    let pickedTeam: String
    let isSuperdog: Bool
    let result: String
    let isForfeit: Bool
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, result
        case userID = "user_id"
        case gameID = "game_id"
        case groupID = "group_id"
        case pickedTeam = "picked_team"
        case isSuperdog = "is_superdog"
        case isForfeit = "is_forfeit"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    func toDomain() -> Pick {
        Pick(
            id: id,
            userID: userID,
            gameID: gameID,
            groupID: groupID,
            pickedTeam: pickedTeam,
            isSuperdog: isSuperdog,
            result: PickResult(rawValue: result) ?? .pending,
            isForfeit: isForfeit,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
