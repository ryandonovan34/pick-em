import Foundation

final class MockPickRepository: PickRepositoryProtocol {
    private var picks: [Pick]

    init(picks: [Pick] = MockData.picks) {
        self.picks = picks
    }

    func fetchPicks(groupID: String, weekID: String) async throws -> [Pick] {
        picks.filter { $0.groupID == groupID }
    }

    func fetchAllPicks(groupID: String) async throws -> [Pick] {
        picks.filter { $0.groupID == groupID && $0.userID == MockData.currentUserID }
    }

    func fetchPickHistory(groupID: String, userID: String) async throws -> [PickHistoryEntry] {
        let gamesByID = Dictionary(uniqueKeysWithValues: MockData.games.map { ($0.id, $0) })
        let weeksByID = Dictionary(uniqueKeysWithValues: MockData.allWeeks.map { ($0.id, $0) })

        return picks
            .filter { $0.groupID == groupID && $0.userID == userID && $0.result != .pending }
            .compactMap { pick -> PickHistoryEntry? in
                guard let game = gamesByID[pick.gameID], let week = weeksByID[game.weekID] else { return nil }
                return PickHistoryEntry(
                    pickID: pick.id,
                    gameID: game.id,
                    weekNumber: week.weekNumber,
                    weekLabel: week.label,
                    homeTeam: game.homeTeam,
                    awayTeam: game.awayTeam,
                    pickedTeam: pick.pickedTeam,
                    favoriteTeam: game.favoriteTeam,
                    spread: game.spread,
                    kickoffAt: game.kickoffAt,
                    isSuperdog: pick.isSuperdog,
                    isForfeit: pick.isForfeit,
                    result: pick.result,
                    homeScore: game.homeScore,
                    awayScore: game.awayScore
                )
            }
            .sorted { $0.kickoffAt < $1.kickoffAt }
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

    func setMissedPick(groupID: String, pickID: String, pickedTeam: String) async throws -> Pick {
        guard let index = picks.firstIndex(where: { $0.id == pickID && $0.groupID == groupID }),
              let game = MockData.games.first(where: { $0.id == picks[index].gameID }),
              let homeScore = game.homeScore, let awayScore = game.awayScore else {
            throw RepositoryError.notFound
        }
        let existing = picks[index]
        guard existing.isForfeit else {
            throw RepositoryError.conflict("This pick wasn't missed, so it can't be changed.")
        }
        let favoriteMargin = game.favoriteTeam == game.homeTeam ? homeScore - awayScore : awayScore - homeScore
        let favoriteCovered = Double(favoriteMargin) > abs(game.spread)
        let won = (pickedTeam == game.favoriteTeam) == favoriteCovered
        let updated = Pick(
            id: existing.id,
            userID: existing.userID,
            gameID: existing.gameID,
            groupID: existing.groupID,
            pickedTeam: pickedTeam,
            isSuperdog: false,
            result: won ? .win : .loss,
            isForfeit: false,
            createdAt: existing.createdAt,
            updatedAt: Date()
        )
        picks[index] = updated
        return updated
    }
}
