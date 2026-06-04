import XCTest
@testable import PickEm

final class GroupModelTests: XCTestCase {

    func testIsSeasonMode_trueForSeason() {
        XCTAssertTrue(makeGroup(mode: .season).isSeasonMode)
    }

    func testIsSeasonMode_falseForWorldCup() {
        XCTAssertFalse(makeGroup(mode: .worldCup).isSeasonMode)
    }

    func testIsWorldCupMode_trueForWorldCup() {
        XCTAssertTrue(makeGroup(mode: .worldCup).isWorldCupMode)
    }

    func testIsWorldCupMode_falseForSeason() {
        XCTAssertFalse(makeGroup(mode: .season).isWorldCupMode)
    }

    func testIsStructuredMode_trueForSeason() {
        XCTAssertTrue(makeGroup(mode: .season).isStructuredMode)
    }

    func testIsStructuredMode_trueForWorldCup() {
        XCTAssertTrue(makeGroup(mode: .worldCup).isStructuredMode)
    }

    private func makeGroup(mode: ChallengeMode) -> Group {
        Group(
            id: "g1", name: "Test", adminID: "u1", joinCode: "ABC123",
            sport: mode == .worldCup ? .worldCup : .nfl,
            mode: mode, seasonYear: 2026,
            blindPicks: false, superdogsEnabled: false, superdogsPerUser: 0,
            createdAt: Date()
        )
    }
}
