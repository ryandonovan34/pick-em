import XCTest
@testable import PickEm

final class GroupModelTests: XCTestCase {

    func testIsSeasonMode_trueForSeason() {
        XCTAssertTrue(makeGroup(mode: .season).isSeasonMode)
    }

    private func makeGroup(mode: ChallengeMode) -> Group {
        Group(
            id: "g1", name: "Test", adminID: "u1", joinCode: "ABC123",
            sport: .nfl,
            mode: mode, seasonYear: 2026,
            blindPicks: false, superdogsEnabled: false, superdogsPerUser: 0,
            includePreseason: false, includePlayoffs: true,
            createdAt: Date()
        )
    }
}
