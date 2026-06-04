import Foundation

final class MockPickRepository: PickRepositoryProtocol {
    private var picks: [Pick] = MockData.picks

    func fetchPicks(groupID: String, weekID: String) async throws -> [Pick] {
        picks.filter { $0.groupID == groupID }
    }

    func submitPick(gameID: String, groupID: String, pickedTeam: String, isSuperdog: Bool) async throws -> Pick {
        if picks.contains(where: { $0.gameID == gameID && $0.groupID == groupID && $0.userID == MockData.currentUserID }) {
            throw RepositoryError.conflict("Pick already exists for this game. Use updatePick to change it.")
        }
        let pick = Pick(
            id: UUID().uuidString,
            userID: MockData.currentUserID,
            gameID: gameID,
            groupID: groupID,
            pickedTeam: pickedTeam,
            isSuperdog: isSuperdog,
            result: .pending,
            createdAt: Date(),
            updatedAt: Date()
        )
        picks.append(pick)
        return pick
    }

    func updatePick(id: String, pickedTeam: String, isSuperdog: Bool) async throws -> Pick {
        guard let index = picks.firstIndex(where: { $0.id == id }) else {
            throw RepositoryError.notFound
        }
        let existing = picks[index]
        let updated = Pick(
            id: existing.id,
            userID: existing.userID,
            gameID: existing.gameID,
            groupID: existing.groupID,
            pickedTeam: pickedTeam,
            isSuperdog: isSuperdog,
            result: existing.result,
            createdAt: existing.createdAt,
            updatedAt: Date()
        )
        picks[index] = updated
        return updated
    }
}
