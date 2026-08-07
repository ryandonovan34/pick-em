import Foundation

final class LivePickRepository: PickRepositoryProtocol {
    private let network: NetworkService

    init(network: NetworkService) {
        self.network = network
    }

    func fetchPicks(groupID: String, weekID: String) async throws -> [Pick] {
        let dtos: [PickDTO] = try await network.get("/groups/\(groupID)/weeks/\(weekID)/picks")
        return dtos.map { $0.toDomain() }
    }

    func fetchAllPicks(groupID: String) async throws -> [Pick] {
        let dtos: [PickDTO] = try await network.get("/groups/\(groupID)/picks")
        return dtos.map { $0.toDomain() }
    }

    func fetchPickHistory(groupID: String, userID: String) async throws -> [PickHistoryEntry] {
        let dtos: [PickHistoryEntryDTO] = try await network.get("/groups/\(groupID)/members/\(userID)/picks/history")
        return dtos.map { $0.toDomain() }
    }

    func submitPick(gameID: String, groupID: String, pickedTeam: String, isSuperdog: Bool) async throws -> Pick {
        struct SubmitPickBody: Encodable {
            let game_id: String; let group_id: String
            let picked_team: String; let is_superdog: Bool
        }
        let body = SubmitPickBody(game_id: gameID, group_id: groupID, picked_team: pickedTeam, is_superdog: isSuperdog)
        let dto: PickDTO = try await network.post("/picks", body: body)
        return dto.toDomain()
    }

    func updatePick(id: String, pickedTeam: String, isSuperdog: Bool) async throws -> Pick {
        struct UpdatePickBody: Encodable { let picked_team: String; let is_superdog: Bool }
        let dto: PickDTO = try await network.put("/picks/\(id)", body: UpdatePickBody(picked_team: pickedTeam, is_superdog: isSuperdog))
        return dto.toDomain()
    }
}
