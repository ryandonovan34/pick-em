import Foundation
import OSLog

/// Pairs a graded pick with the running win/loss tally through that pick —
/// wins count superdog wins as +3, matching Standing.record/winPercentage
/// and the backend's own standings computation
/// (pickem-api/app/schemas/standing.py).
struct PlayerHistoryRow: Identifiable {
    let entry: PickHistoryEntry
    let winsAfter: Int
    let lossesAfter: Int
    var id: String { entry.id }
    var recordAfter: String { "\(winsAfter)-\(lossesAfter)" }
}

@Observable
@MainActor
final class PlayerHistoryViewModel {
    var entries: [PickHistoryEntry] = []
    var isLoading = false
    var errorMessage: String?
    var isSettingMissedPick = false
    /// Separate from errorMessage, which only shows when there's no history to display.
    var missedPickErrorMessage: String?

    let group: Group
    let userID: String
    let displayName: String

    private let currentUserID: String
    private let pickRepository: any PickRepositoryProtocol
    private let onMissedPickSet: () async -> Void

    init(
        group: Group,
        userID: String,
        displayName: String,
        currentUserID: String,
        pickRepository: any PickRepositoryProtocol,
        onMissedPickSet: @escaping () async -> Void = {}
    ) {
        self.group = group
        self.userID = userID
        self.displayName = displayName
        self.currentUserID = currentUserID
        self.pickRepository = pickRepository
        self.onMissedPickSet = onMissedPickSet
    }

    /// Only the group admin, and only for other members' missed picks.
    var canSetMissedPicks: Bool {
        group.adminID == currentUserID && userID != currentUserID
    }

    var rows: [PlayerHistoryRow] {
        var wins = 0
        var losses = 0
        return entries.map { entry in
            wins += entry.result.winCount
            if entry.result == .loss { losses += 1 }
            return PlayerHistoryRow(entry: entry, winsAfter: wins, lossesAfter: losses)
        }
    }

    func loadHistory() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            entries = try await pickRepository.fetchPickHistory(groupID: group.id, userID: userID)
            Self.diagnosticLogger.debug("PlayerHistory OK group=\(self.group.id, privacy: .public) user=\(self.userID, privacy: .public) count=\(self.entries.count, privacy: .public)")
        } catch {
            errorMessage = "Failed to fetch pick history: \(error.localizedDescription)"
            Self.diagnosticLogger.error("PlayerHistory FAILED group=\(self.group.id, privacy: .public) user=\(self.userID, privacy: .public) error=\(String(describing: error), privacy: .public)")
        }
    }

    func setMissedPick(_ entry: PickHistoryEntry, pickedTeam: String) async {
        isSettingMissedPick = true
        missedPickErrorMessage = nil
        defer { isSettingMissedPick = false }
        do {
            _ = try await pickRepository.setMissedPick(groupID: group.id, pickID: entry.pickID, pickedTeam: pickedTeam)
        } catch {
            missedPickErrorMessage = "Failed to set pick: \(error.localizedDescription)"
            return
        }
        await loadHistory()
        await onMissedPickSet()
    }

    // TEMPORARY — diagnosing a report of "No Graded Picks Yet" despite the
    // server having fully graded data for every user tested. Remove once
    // root-caused. Explicitly public: only UUIDs and a count, nothing
    // sensitive, unlike NetworkLogger's full request/response bodies (which
    // include passwords/tokens and must stay private).
    private static let diagnosticLogger = Logger(subsystem: "com.pickem", category: "PlayerHistoryDebug")
}
