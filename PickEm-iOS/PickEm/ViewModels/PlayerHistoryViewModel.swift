import Foundation

/// Pairs a graded pick with the running win/loss tally through that pick —
/// wins count superdog wins as +3, matching how the backend's standings
/// record is actually computed (Standing.record/winPercentage on iOS don't
/// weight superdog wins the same way, but this view exists specifically to
/// verify that real record, so it must match it).
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

    let group: Group
    let userID: String
    let displayName: String

    private let pickRepository: any PickRepositoryProtocol

    init(group: Group, userID: String, displayName: String, pickRepository: any PickRepositoryProtocol) {
        self.group = group
        self.userID = userID
        self.displayName = displayName
        self.pickRepository = pickRepository
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
        } catch {
            errorMessage = "Failed to fetch pick history: \(error.localizedDescription)"
        }
    }
}
