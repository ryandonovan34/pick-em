import XCTest
@testable import PickEm

final class GameModelTests: XCTestCase {

    // MARK: - Spread Rounding

    func testSpreadRounding_negativeWhole_roundsAwayFromZero() {
        XCTAssertEqual(Game.roundedSpread(-3.0), -3.5)
        XCTAssertEqual(Game.roundedSpread(-7.0), -7.5)
        XCTAssertEqual(Game.roundedSpread(-10.0), -10.5)
    }

    func testSpreadRounding_positiveWhole_roundsAwayFromZero() {
        XCTAssertEqual(Game.roundedSpread(3.0), 3.5)
        XCTAssertEqual(Game.roundedSpread(7.0), 7.5)
    }

    func testSpreadRounding_alreadyHalfPoint_unchanged() {
        XCTAssertEqual(Game.roundedSpread(-3.5), -3.5)
        XCTAssertEqual(Game.roundedSpread(3.5), 3.5)
        XCTAssertEqual(Game.roundedSpread(-7.5), -7.5)
    }

    // MARK: - Superdog Eligibility

    func testSuperdogEligible_spreadAbove6_5() {
        let game = makeGame(spread: -7.5)
        XCTAssertTrue(game.isSuperdogEligible)
    }

    func testSuperdogEligible_spreadExactly6_5() {
        let game = makeGame(spread: -6.5)
        XCTAssertTrue(game.isSuperdogEligible)
    }

    func testSuperdogNotEligible_spreadBelow6_5() {
        let game = makeGame(spread: -3.5)
        XCTAssertFalse(game.isSuperdogEligible)
    }

    func testSuperdogNotEligible_positiveSmallSpread() {
        let game = makeGame(spread: 3.5)
        XCTAssertFalse(game.isSuperdogEligible)
    }

    // MARK: - Lock State

    func testGameIsLocked_afterKickoff() {
        let game = makeGame(kickoffAt: Date(timeIntervalSinceNow: -60))
        XCTAssertTrue(game.isLocked)
    }

    func testGameIsNotLocked_beforeKickoff() {
        let game = makeGame(kickoffAt: Date(timeIntervalSinceNow: 3600))
        XCTAssertFalse(game.isLocked)
    }

    // MARK: - Underdog

    func testUnderdogTeam_isOppositeOfFavorite() {
        let game = makeGame(homeTeam: "Chiefs", awayTeam: "Raiders", favoriteTeam: "Chiefs", spread: -7.5)
        XCTAssertEqual(game.underdogTeam, "Raiders")
    }

    // MARK: - Spread Display

    func testSpreadDisplay_favoriteHomeTeam_showsNegativeSpread() {
        let game = makeGame(homeTeam: "Chiefs", awayTeam: "Raiders", favoriteTeam: "Chiefs", spread: -7.5)
        XCTAssertEqual(game.spreadDisplay, "Chiefs -7.5")
    }

    func testSpreadDisplay_underdogHome_showsPlusSpread() {
        let game = makeGame(homeTeam: "Raiders", awayTeam: "Chiefs", favoriteTeam: "Chiefs", spread: 7.5)
        XCTAssertEqual(game.spreadDisplay, "Chiefs +7.5")
    }

    // MARK: - hasKickedOff

    func testHasKickedOff_pastKickoff_returnsTrue() {
        let game = makeGame(kickoffAt: Date(timeIntervalSinceNow: -1))
        XCTAssertTrue(game.hasKickedOff)
    }

    func testHasKickedOff_futureKickoff_returnsFalse() {
        let game = makeGame(kickoffAt: Date(timeIntervalSinceNow: 3600))
        XCTAssertFalse(game.hasKickedOff)
    }

    // MARK: - Helpers

    private func makeGame(
        homeTeam: String = "Home",
        awayTeam: String = "Away",
        favoriteTeam: String = "Home",
        spread: Double = -3.5,
        kickoffAt: Date = Date(timeIntervalSinceNow: 3600)
    ) -> Game {
        Game(
            id: UUID().uuidString,
            weekID: "week-1",
            oddsAPIID: nil,
            sport: .nfl,
            homeTeam: homeTeam,
            awayTeam: awayTeam,
            spread: spread,
            favoriteTeam: favoriteTeam,
            kickoffAt: kickoffAt,
            homeScore: nil,
            awayScore: nil,
            resultPosted: false
        )
    }
}
