import XCTest
@testable import PickEm

@MainActor
final class PickViewModelTests: XCTestCase {
    private var viewModel: PickViewModel!

    override func setUp() {
        super.setUp()
        viewModel = PickViewModel(
            group: MockData.group,
            currentUserID: MockData.currentUserID,
            pickRepository: MockPickRepository()
        )
    }

    func testLoadPicks_populatesCurrentUserPicks() async {
        await viewModel.loadPicks(weekID: MockData.week.id)
        XCTAssertFalse(viewModel.picks.isEmpty)
    }

    func testSubmitPick_forNewGame() async {
        await viewModel.loadPicks(weekID: MockData.week.id)
        let game = MockData.games[1] // game-2, no existing pick
        XCTAssertNil(viewModel.pick(for: game))
        await viewModel.submitOrUpdate(game: game, pickedTeam: game.homeTeam, isSuperdog: false)
        XCTAssertNotNil(viewModel.pick(for: game))
        XCTAssertNil(viewModel.errorMessage)
    }

    func testUpdatePick_changesTeam() async {
        await viewModel.loadPicks(weekID: MockData.week.id)
        let game = MockData.games[0] // game-1, existing pick for Chiefs
        XCTAssertEqual(viewModel.pick(for: game)?.pickedTeam, "Kansas City Chiefs")
        await viewModel.submitOrUpdate(game: game, pickedTeam: game.awayTeam, isSuperdog: false)
        XCTAssertEqual(viewModel.pick(for: game)?.pickedTeam, game.awayTeam)
    }

    func testSubmitPick_onLockedGame_setsError() async {
        let lockedGame = MockData.games[3] // game-4, already kicked off
        await viewModel.submitOrUpdate(game: lockedGame, pickedTeam: lockedGame.homeTeam, isSuperdog: false)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testSuperdogPick_onIneligibleGame_setsError() async {
        let smallSpreadGame = MockData.games[1] // -3.5 spread, not eligible
        await viewModel.submitOrUpdate(game: smallSpreadGame, pickedTeam: smallSpreadGame.underdogTeam, isSuperdog: true)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testSuperdogPick_whenSuperdogsDisabled_setsError() async {
        let disabledGroup = Group(
            id: "g2", name: "No Dogs", adminID: "u1", joinCode: "NODGS1",
            sport: .nfl, mode: .season, seasonYear: 2025,
            blindPicks: false, superdogsEnabled: false, superdogsPerUser: 3,
            includePreseason: false, includePlayoffs: true,
            createdAt: Date()
        )
        let vm = PickViewModel(
            group: disabledGroup,
            currentUserID: MockData.currentUserID,
            pickRepository: MockPickRepository()
        )
        let bigSpreadGame = MockData.games[2] // -10.5 spread
        await vm.submitOrUpdate(game: bigSpreadGame, pickedTeam: bigSpreadGame.underdogTeam, isSuperdog: true)
        XCTAssertNotNil(vm.errorMessage)
    }
}
