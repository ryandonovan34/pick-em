import Foundation

struct Pick: Identifiable, Equatable {
    let id: String
    let userID: String
    let gameID: String
    let groupID: String
    let pickedTeam: String
    let isSuperdog: Bool
    let result: PickResult
    /// True when this pick was auto-created because the user never picked
    /// before kickoff — always paired with result == .loss.
    let isForfeit: Bool
    let createdAt: Date
    let updatedAt: Date

    init(id: String, userID: String, gameID: String, groupID: String, pickedTeam: String, isSuperdog: Bool, result: PickResult, isForfeit: Bool = false, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.userID = userID
        self.gameID = gameID
        self.groupID = groupID
        self.pickedTeam = pickedTeam
        self.isSuperdog = isSuperdog
        self.result = result
        self.isForfeit = isForfeit
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
