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

    private func makeStanding(wins: Int, losses: Int) -> Standing {
        Standing(
            userID: "u1", groupID: "g1", displayName: "Alice",
            wins: wins, losses: losses,
            superdogWins: 0, superdogsUsed: 0,
            updatedAt: Date()
        )
    }
}
