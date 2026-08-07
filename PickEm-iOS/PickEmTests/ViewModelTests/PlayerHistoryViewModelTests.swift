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
