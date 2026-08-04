import Foundation

final class LiveGroupRepository: GroupRepositoryProtocol {
    private let network: NetworkService

    init(network: NetworkService) {
        self.network = network
    }

    func fetchGroups() async throws -> [Group] {
        let dtos: [GroupDTO] = try await network.get("/groups")
        return dtos.map { $0.toDomain() }
    }

    func fetchGroup(id: String) async throws -> Group {
        let dto: GroupDTO = try await network.get("/groups/\(id)")
        return dto.toDomain()
    }

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
    ) async throws -> Group {
        struct CreateGroupBody: Encodable {
            let name: String; let sport: String; let mode: String
            let season_year: Int?; let blind_picks: Bool
            let superdogs_enabled: Bool; let superdogs_per_user: Int
            let include_preseason: Bool; let include_playoffs: Bool
        }
        let body = CreateGroupBody(
            name: name, sport: sport.rawValue, mode: mode.rawValue,
            season_year: seasonYear, blind_picks: blindPicks,
            superdogs_enabled: superdogsEnabled, superdogs_per_user: superdogsPerUser,
            include_preseason: includePreseason, include_playoffs: includePlayoffs
        )
        let dto: GroupDTO = try await network.post("/groups", body: body)
        return dto.toDomain()
    }

    func joinGroup(joinCode: String) async throws -> Group {
        struct JoinBody: Encodable { let join_code: String }
        let dto: GroupDTO = try await network.post("/groups/join", body: JoinBody(join_code: joinCode))
        return dto.toDomain()
    }

    func removeMember(groupID: String, userID: String) async throws {
        try await network.delete("/groups/\(groupID)/members/\(userID)")
    }
}
