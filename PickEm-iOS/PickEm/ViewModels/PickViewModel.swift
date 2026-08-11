import Foundation

@Observable
@MainActor
final class PickViewModel {
    var picks: [String: Pick] = [:]  // keyed by gameID — current user's own pick only
    /// Every visible member's pick for a week, keyed by gameID (blind-pick
    /// filtering already enforced server-side — this is exactly whatever
    /// GET .../weeks/{weekID}/picks returns). Loaded separately from
    /// `picks` and never merged into it: `picks` is relied on elsewhere
    /// (e.g. SlateView's per-week pick-count badges) to hold the current
    /// user's own picks across ALL weeks at once, keyed globally by
    /// gameID — narrowing it down to just one week's games here would
    /// silently break those counts for every other week.
    var allMemberPicks: [String: [Pick]] = [:]
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

    /// Everyone's visible picks for a week — used to show what each member
    /// picked under a game row.
    func loadAllMemberPicks(weekID: String) async {
        errorMessage = nil
        do {
            let weekPicks = try await pickRepository.fetchPicks(groupID: group.id, weekID: weekID)
            allMemberPicks = Dictionary(grouping: weekPicks, by: \.gameID)
        } catch {
            errorMessage = "Failed to retrieve picks: \(error.localizedDescription)"
        }
    }

    func memberPicks(for game: Game) -> [Pick] {
        allMemberPicks[game.id] ?? []
    }

    func loadAllPicks(groupID: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let allPicks = try await pickRepository.fetchAllPicks(groupID: groupID)
            picks = Dictionary(uniqueKeysWithValues: allPicks.map { ($0.gameID, $0) })
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
                upsertMemberPick(updated)
            } else {
                let pick = try await pickRepository.submitPick(gameID: game.id, groupID: group.id, pickedTeam: pickedTeam, isSuperdog: isSuperdog)
                picks[game.id] = pick
                upsertMemberPick(pick)
            }
        } catch {
            errorMessage = "Failed to submit pick. Please try again later."
        }
    }

    /// Keeps allMemberPicks in sync after the current user submits/changes
    /// their own pick, so it shows up immediately without a full reload.
    private func upsertMemberPick(_ pick: Pick) {
        var forGame = allMemberPicks[pick.gameID] ?? []
        if let index = forGame.firstIndex(where: { $0.userID == pick.userID }) {
            forGame[index] = pick
        } else {
            forGame.append(pick)
        }
        allMemberPicks[pick.gameID] = forGame
    }

    func pick(for game: Game) -> Pick? {
        picks[game.id]
    }
}
