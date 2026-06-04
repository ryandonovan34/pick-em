import Foundation

struct Pick: Identifiable, Equatable {
    let id: String
    let userID: String
    let gameID: String
    let groupID: String
    let pickedTeam: String
    let isSuperdog: Bool
    let result: PickResult
    let createdAt: Date
    let updatedAt: Date
}
