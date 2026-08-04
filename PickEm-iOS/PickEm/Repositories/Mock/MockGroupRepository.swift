import Foundation

final class MockGroupRepository: GroupRepositoryProtocol {
    private var groups: [Group] = [MockData.nflGroup]

    func fetchGroups() async throws -> [Group] {
        groups
    }

    func fetchGroup(id: String) async throws -> Group {
        guard let group = groups.first(where: { $0.id == id }) else {
            throw RepositoryError.notFound
        }
        return group
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
        let group = Group(
            id: UUID().uuidString,
            name: name,
            adminID: MockData.currentUserID,
            joinCode: String(UUID().uuidString.prefix(6).uppercased()),
            sport: sport,
            mode: mode,
            seasonYear: seasonYear,
            blindPicks: blindPicks,
            superdogsEnabled: superdogsEnabled,
            superdogsPerUser: superdogsPerUser,
            includePreseason: includePreseason,
            includePlayoffs: includePlayoffs,
            createdAt: Date()
        )
        groups.append(group)
        return group
    }

    func joinGroup(joinCode: String) async throws -> Group {
        guard let group = groups.first(where: { $0.joinCode == joinCode }) else {
            throw RepositoryError.notFound
        }
        return group
    }

    func removeMember(groupID: String, userID: String) async throws {}
}
