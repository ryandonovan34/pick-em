import Foundation

protocol PickRepositoryProtocol {
    func fetchPicks(groupID: String, weekID: String) async throws -> [Pick]
    func fetchAllPicks(groupID: String) async throws -> [Pick]
    /// A member's full history of GRADED picks (never .pending) in a group,
    /// chronological by kickoff — for verifying their win/loss record.
    func fetchPickHistory(groupID: String, userID: String) async throws -> [PickHistoryEntry]
    func submitPick(gameID: String, groupID: String, pickedTeam: String, isSuperdog: Bool) async throws -> Pick
    func updatePick(id: String, pickedTeam: String, isSuperdog: Bool) async throws -> Pick
}
