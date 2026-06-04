import Foundation

protocol PickRepositoryProtocol {
    func fetchPicks(groupID: String, weekID: String) async throws -> [Pick]
    func submitPick(gameID: String, groupID: String, pickedTeam: String, isSuperdog: Bool) async throws -> Pick
    func updatePick(id: String, pickedTeam: String, isSuperdog: Bool) async throws -> Pick
}
