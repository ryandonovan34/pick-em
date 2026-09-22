import XCTest
@testable import PickEm

final class StandingModelTests: XCTestCase {

    func testWinPercentage_correctlyCalculated() {
        let standing = makeStanding(wins: 7, losses: 3)
        XCTAssertEqual(standing.winPercentage, 0.7, accuracy: 0.001)
    }

    func testWinPercentage_zeroGames_returnsZero() {
        let standing = makeStanding(wins: 0, losses: 0)
        XCTAssertEqual(standing.winPercentage, 0.0)
    }

    func testRecord_formatsCorrectly() {
        let standing = makeStanding(wins: 7, losses: 3)
        XCTAssertEqual(standing.record, "7-3")
    }

    func testTotalGames() {
        let standing = makeStanding(wins: 7, losses: 3)
        XCTAssertEqual(standing.totalGames, 10)
    }

    // A superdog win is worth 3 regular wins — matches the backend's own
    // StandingRead.record/win_percentage computation. E.g. Marty: 7 regular
    // wins + 1 superdog win + 12 losses should read "10-12", not "7-12".
    func testRecord_withSuperdogWins_weighsEachAsThreeWins() {
        let standing = makeStanding(wins: 7, losses: 12, superdogWins: 1)
        XCTAssertEqual(standing.record, "10-12")
    }

    func testWinPercentage_withSuperdogWins_weighsEachAsThreeWins() {
        let standing = makeStanding(wins: 7, losses: 12, superdogWins: 1)
        XCTAssertEqual(standing.winPercentage, 10.0 / 22.0, accuracy: 0.001)
    }

    func testTotalGames_withSuperdogWins_includesBonusWins() {
        let standing = makeStanding(wins: 7, losses: 12, superdogWins: 1)
        XCTAssertEqual(standing.totalGames, 22)
    }

    private func makeStanding(wins: Int, losses: Int, superdogWins: Int = 0) -> Standing {
        Standing(
            userID: "u1", groupID: "g1", displayName: "Alice",
            wins: wins, losses: losses,
            superdogWins: superdogWins, superdogsUsed: 0,
            updatedAt: Date()
        )
    }
}
