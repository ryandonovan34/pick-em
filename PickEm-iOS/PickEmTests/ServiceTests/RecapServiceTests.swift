import XCTest
@testable import PickEm

final class RecapServiceTests: XCTestCase {
    private var game4Picks: [String: [Pick]] {
        Dictionary(grouping: MockData.picks.filter { $0.gameID == "game-4" }, by: \.gameID)
    }

    func testBuildPrompt_includesFinalScoreForPostedResults() {
        let prompt = RecapService.buildPrompt(games: MockData.nflGames, memberPicks: game4Picks, standings: MockData.standings)

        XCTAssertTrue(prompt.contains("Miami Dolphins 14 @ Buffalo Bills 27"))
    }

    func testBuildPrompt_excludesGamesWithoutPostedResults() {
        // game-1 has resultPosted == false, so it must never show up in the summary.
        let prompt = RecapService.buildPrompt(games: MockData.nflGames, memberPicks: [:], standings: [])

        XCTAssertFalse(prompt.contains("Kansas City Chiefs"))
    }

    func testBuildPrompt_describesEachMembersOutcome() {
        let prompt = RecapService.buildPrompt(games: MockData.nflGames, memberPicks: game4Picks, standings: MockData.standings)

        XCTAssertTrue(prompt.contains("Alice picked Buffalo Bills and won."))
        XCTAssertTrue(prompt.contains("Bob picked Miami Dolphins and lost."))
        XCTAssertTrue(prompt.contains("Charlie picked Buffalo Bills and won."))
    }

    func testBuildPrompt_includesStandingsRecords() {
        let prompt = RecapService.buildPrompt(games: [], memberPicks: [:], standings: MockData.standings)

        XCTAssertTrue(prompt.contains("Current standings:"))
        for standing in MockData.standings {
            XCTAssertTrue(prompt.contains("\(standing.displayName): \(standing.record)"))
        }
    }

    func testBuildPrompt_withNoStandings_omitsStandingsSection() {
        let prompt = RecapService.buildPrompt(games: [], memberPicks: [:], standings: [])

        XCTAssertFalse(prompt.contains("Current standings:"))
    }
}
