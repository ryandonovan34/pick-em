import Foundation

protocol GroupRepositoryProtocol {
    func fetchGroups() async throws -> [Group]
    func fetchGroup(id: String) async throws -> Group
    func createGroup(
        name: String,
        sport: Sport,
        mode: ChallengeMode,
        seasonYear: Int?,
        blindPicks: Bool,
        superdogsEnabled: Bool,
        superdogsPerUser: Int,
        includePreseason: Bool,
        includePlayoffs: Bool
    ) async throws -> Group
    func joinGroup(joinCode: String) async throws -> Group
    func removeMember(groupID: String, userID: String) async throws
}
