import XCTest
@testable import PickEm

@MainActor
final class SlateViewModelTests: XCTestCase {
    private var viewModel: SlateViewModel!

    override func setUp() {
        super.setUp()
        viewModel = SlateViewModel(
            group: MockData.group,
            gameRepository: MockGameRepository()
        )
    }

    func testLoadWeeks_populatesWeeks() async {
        await viewModel.loadWeeks()
        XCTAssertFalse(viewModel.weeks.isEmpty)
        XCTAssertNotNil(viewModel.selectedWeek)
    }

    func testLoadWeeks_selectsCurrentWeekNotEmptyUpcomingWeek() async {
        // Regression test: mostRelevantWeek() depends on firstKickoffAt/lastKickoffAt
        // being populated for the in-progress week. If they're missing (as they
        // were before MockData.swift set them), this silently falls through to
        // selecting the next upcoming (and here, empty-of-picks) week instead —
        // the exact bug that made MockLocal look "messed up" on launch.
        await viewModel.loadWeeks()
        XCTAssertEqual(viewModel.selectedWeek?.id, MockData.nflWeek.id)
    }

    func testLoadWeeks_loadsGamesForLatestWeek() async {
        await viewModel.loadWeeks()
        XCTAssertFalse(viewModel.games.isEmpty)
    }

    func testSelectWeek_loadsGamesForThatWeek() async {
        await viewModel.loadWeeks()
        let week = viewModel.weeks[0]
        await viewModel.selectWeek(week)
        XCTAssertEqual(viewModel.selectedWeek, week)
        XCTAssertFalse(viewModel.games.isEmpty)
    }
}
