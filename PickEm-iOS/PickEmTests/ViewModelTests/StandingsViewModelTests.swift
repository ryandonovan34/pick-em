import XCTest
@testable import PickEm

@MainActor
final class StandingsViewModelTests: XCTestCase {
    private var viewModel: StandingsViewModel!

    override func setUp() {
        super.setUp()
        viewModel = StandingsViewModel(
            group: MockData.group,
            standingsRepository: MockStandingsRepository()
        )
    }

    func testLoadStandings_populatesData() async {
        await viewModel.loadStandings()
        XCTAssertFalse(viewModel.standings.isEmpty)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testStandings_sortedByWinPercentage() async {
        await viewModel.loadStandings()
        let pcts = viewModel.standings.map(\.winPercentage)
        XCTAssertEqual(pcts, pcts.sorted(by: >))
    }
}
