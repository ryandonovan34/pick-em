import XCTest
@testable import PickEm

@MainActor
final class PlayerHistoryViewModelTests: XCTestCase {
    private var viewModel: PlayerHistoryViewModel!

    override func setUp() {
        super.setUp()
        viewModel = PlayerHistoryViewModel(
            group: MockData.group,
            userID: MockData.currentUserID,
            displayName: "Alice",
            currentUserID: MockData.currentUserID,
            pickRepository: MockPickRepository()
        )
    }

    func testLoadHistory_populatesEntries() async {
        await viewModel.loadHistory()
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.entries.isEmpty)
    }

    func testLoadHistory_excludesPendingEntries() async {
        await viewModel.loadHistory()
        XCTAssertTrue(viewModel.entries.allSatisfy { $0.result != .pending })
    }

    func testRows_computesRunningTally_winsAndLosses() {
        viewModel.entries = [
            makeEntry(result: .win),
            makeEntry(result: .loss),
            makeEntry(result: .win),
        ]
        let rows = viewModel.rows
        XCTAssertEqual(rows.map(\.winsAfter), [1, 1, 2])
        XCTAssertEqual(rows.map(\.lossesAfter), [0, 1, 1])
        XCTAssertEqual(rows.last?.recordAfter, "2-1")
    }

    func testRows_superdogWinCountsAsThreeWins() {
        viewModel.entries = [
            makeEntry(result: .superdogWin, isSuperdog: true),
            makeEntry(result: .loss),
        ]
        let rows = viewModel.rows
        XCTAssertEqual(rows[0].winsAfter, 3)
        XCTAssertEqual(rows[0].recordAfter, "3-0")
        XCTAssertEqual(rows[1].recordAfter, "3-1")
    }

    func testRows_emptyEntries_producesEmptyRows() {
        viewModel.entries = []
        XCTAssertTrue(viewModel.rows.isEmpty)
    }

    func testCanSetMissedPicks_adminViewingOtherMember() {
        XCTAssertTrue(makeMissedPickViewModel(viewedUserID: MockData.otherUserID, currentUserID: MockData.adminUserID).canSetMissedPicks)
    }

    func testCanSetMissedPicks_falseForAdminsOwnHistory() {
        XCTAssertFalse(makeMissedPickViewModel(viewedUserID: MockData.adminUserID, currentUserID: MockData.adminUserID).canSetMissedPicks)
    }

    func testCanSetMissedPicks_falseForNonAdmin() {
        XCTAssertFalse(makeMissedPickViewModel(viewedUserID: MockData.thirdUserID, currentUserID: MockData.otherUserID).canSetMissedPicks)
    }

    func testSetMissedPick_gradesPickReloadsHistoryAndNotifies() async throws {
        var notified = false
        let vm = makeMissedPickViewModel(
            viewedUserID: MockData.otherUserID,
            currentUserID: MockData.adminUserID,
            onMissedPickSet: { notified = true }
        )
        await vm.loadHistory()
        let forfeit = try XCTUnwrap(vm.entries.first)
        XCTAssertTrue(forfeit.isForfeit)

        // game-4: Bills -4.5 won 27-14, so the Bills covered.
        await vm.setMissedPick(forfeit, pickedTeam: "Buffalo Bills")

        XCTAssertNil(vm.missedPickErrorMessage)
        XCTAssertFalse(vm.entries[0].isForfeit)
        XCTAssertEqual(vm.entries[0].pickedTeam, "Buffalo Bills")
        XCTAssertEqual(vm.entries[0].result, .win)
        XCTAssertTrue(notified)
    }

    func testSetMissedPick_failureSetsErrorAndDoesNotNotify() async throws {
        var notified = false
        let vm = makeMissedPickViewModel(
            viewedUserID: MockData.otherUserID,
            currentUserID: MockData.adminUserID,
            onMissedPickSet: { notified = true }
        )
        await vm.loadHistory()
        let forfeit = try XCTUnwrap(vm.entries.first)
        await vm.setMissedPick(forfeit, pickedTeam: "Buffalo Bills")
        notified = false

        // The pick is no longer missed, so setting it a second time is rejected.
        await vm.setMissedPick(forfeit, pickedTeam: "Miami Dolphins")

        XCTAssertNotNil(vm.missedPickErrorMessage)
        XCTAssertFalse(notified)
        XCTAssertEqual(vm.entries[0].pickedTeam, "Buffalo Bills")
    }

    private func makeMissedPickViewModel(
        viewedUserID: String,
        currentUserID: String,
        onMissedPickSet: @escaping () async -> Void = {}
    ) -> PlayerHistoryViewModel {
        let forfeit = Pick(
            id: "forfeit-1", userID: viewedUserID, gameID: "game-4", groupID: MockData.group.id,
            pickedTeam: "", isSuperdog: false, result: .loss, isForfeit: true,
            createdAt: Date(), updatedAt: Date()
        )
        return PlayerHistoryViewModel(
            group: MockData.group,
            userID: viewedUserID,
            displayName: "Bob",
            currentUserID: currentUserID,
            pickRepository: MockPickRepository(picks: [forfeit]),
            onMissedPickSet: onMissedPickSet
        )
    }

    private func makeEntry(result: PickResult, isSuperdog: Bool = false) -> PickHistoryEntry {
        PickHistoryEntry(
            pickID: UUID().uuidString,
            gameID: UUID().uuidString,
            weekNumber: 1,
            weekLabel: "Week 1",
            homeTeam: "Kansas City Chiefs",
            awayTeam: "Las Vegas Raiders",
            pickedTeam: "Kansas City Chiefs",
            favoriteTeam: "Kansas City Chiefs",
            spread: -7.5,
            kickoffAt: Date(),
            isSuperdog: isSuperdog,
            isForfeit: false,
            result: result,
            homeScore: 27,
            awayScore: 14
        )
    }
}
