import XCTest
@testable import PickEm

final class MockPickRepositoryTests: XCTestCase {
    private var repo: MockPickRepository!

    override func setUp() {
        super.setUp()
        repo = MockPickRepository()
    }

    func testFetchPicks_returnsPicksForGroup() async throws {
        let picks = try await repo.fetchPicks(groupID: "group-1", weekID: "week-1")
        XCTAssertFalse(picks.isEmpty)
    }

    func testSubmitPick_succeeds() async throws {
        let pick = try await repo.submitPick(
            gameID: "game-2",
            groupID: "group-1",
            pickedTeam: "San Francisco 49ers",
            isSuperdog: false
        )
        XCTAssertEqual(pick.pickedTeam, "San Francisco 49ers")
        XCTAssertEqual(pick.result, .pending)
    }

    func testSubmitPick_duplicateThrowsConflict() async {
        do {
            _ = try await repo.submitPick(gameID: "game-1", groupID: "group-1", pickedTeam: "Raiders", isSuperdog: false)
            XCTFail("Expected conflict error")
        } catch RepositoryError.conflict {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testUpdatePick_changesTeam() async throws {
        let updated = try await repo.updatePick(id: "pick-1", pickedTeam: "Las Vegas Raiders", isSuperdog: false)
        XCTAssertEqual(updated.pickedTeam, "Las Vegas Raiders")
    }

    func testUpdatePick_unknownID_throwsNotFound() async {
        do {
            _ = try await repo.updatePick(id: "no-such-id", pickedTeam: "Raiders", isSuperdog: false)
            XCTFail("Expected notFound error")
        } catch RepositoryError.notFound {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
