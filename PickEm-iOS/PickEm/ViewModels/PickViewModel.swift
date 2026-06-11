import Foundation

@Observable
@MainActor
final class PickViewModel {
    var picks: [String: Pick] = [:]  // keyed by gameID
    var isLoading = false
    var errorMessage: String?

    private let pickRepository: any PickRepositoryProtocol
    let group: Group
    var currentUserID: String

    init(group: Group, currentUserID: String, pickRepository: any PickRepositoryProtocol) {
        self.group = group
        self.currentUserID = currentUserID
        self.pickRepository = pickRepository
    }

    func loadPicks(weekID: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let allPicks = try await pickRepository.fetchPicks(groupID: group.id, weekID: weekID)
            picks = Dictionary(uniqueKeysWithValues: allPicks
                .filter { $0.userID == currentUserID }
                .map { ($0.gameID, $0) })
        } catch {
            errorMessage = "Failed to retrieve picks: \(error.localizedDescription)"
        }
    }

    func submitOrUpdate(game: Game, pickedTeam: String, isSuperdog: Bool) async {
        guard !game.isLocked else {
            errorMessage = "This game has already kicked off."
            return
        }
        if isSuperdog {
            guard group.superdogsEnabled else {
                errorMessage = "Superdogs are not enabled for this group."
                return
            }
            guard game.isSuperdogEligible else {
                errorMessage = "The spread must be at least 6.5 to declare a superdog."
                return
            }
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            if let existing = picks[game.id] {
                let updated = try await pickRepository.updatePick(id: existing.id, pickedTeam: pickedTeam, isSuperdog: isSuperdog)
                picks[game.id] = updated
            } else {
                let pick = try await pickRepository.submitPick(gameID: game.id, groupID: group.id, pickedTeam: pickedTeam, isSuperdog: isSuperdog)
                picks[game.id] = pick
            }
        } catch {
            errorMessage = "Failed to submit pick. Please try again later."
        }
    }

    func pick(for game: Game) -> Pick? {
        picks[game.id]
    }
}
