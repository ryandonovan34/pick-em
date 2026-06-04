import XCTest
@testable import PickEm

final class PickResultTests: XCTestCase {

    // MARK: - winCount

    func testWinCount_win_returnsOne() {
        XCTAssertEqual(PickResult.win.winCount, 1)
    }

    func testWinCount_superdogWin_returnsThree() {
        XCTAssertEqual(PickResult.superdogWin.winCount, 3)
    }

    func testWinCount_loss_returnsZero() {
        XCTAssertEqual(PickResult.loss.winCount, 0)
    }

    func testWinCount_pending_returnsZero() {
        XCTAssertEqual(PickResult.pending.winCount, 0)
    }

    // MARK: - displayName

    func testDisplayName_win() {
        XCTAssertEqual(PickResult.win.displayName, "Win")
    }

    func testDisplayName_loss() {
        XCTAssertEqual(PickResult.loss.displayName, "Loss")
    }

    func testDisplayName_superdogWin() {
        XCTAssertEqual(PickResult.superdogWin.displayName, "Superdog Win")
    }

    func testDisplayName_pending() {
        XCTAssertEqual(PickResult.pending.displayName, "Pending")
    }

    // MARK: - Raw value round-trip (Codable)

    func testRawValue_superdogWin_usesSnakeCase() {
        XCTAssertEqual(PickResult.superdogWin.rawValue, "superdog_win")
    }

    func testInit_fromRawValue_superdogWin() {
        XCTAssertEqual(PickResult(rawValue: "superdog_win"), .superdogWin)
    }

    func testInit_fromUnknownRawValue_returnsNil() {
        XCTAssertNil(PickResult(rawValue: "garbage"))
    }
}
