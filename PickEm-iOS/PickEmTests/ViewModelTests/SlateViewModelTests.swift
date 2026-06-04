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
