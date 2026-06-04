import XCTest
@testable import PickEm

final class DTOMappingTests: XCTestCase {

    // MARK: - GameDTO

    func testGameDTO_mapsToDomain() throws {
        let dto = GameDTO(
            id: "g1", weekID: "w1", oddsAPIID: "odds-1",
            sport: "americanfootball_nfl",
            homeTeam: "Chiefs", awayTeam: "Raiders",
            spread: -7.5, favoriteTeam: "Chiefs",
            kickoffAt: "2025-11-16T18:00:00Z",
            homeScore: nil, awayScore: nil, resultPosted: false
        )
        let game = dto.toDomain()
        XCTAssertEqual(game.id, "g1")
        XCTAssertEqual(game.sport, .nfl)
        XCTAssertEqual(game.spread, -7.5)
        XCTAssertFalse(game.resultPosted)
    }

    func testGameDTO_worldCupSport_mapsToWorldCup() {
        let dto = makeGameDTO(sport: "soccer_fifa_world_cup")
        XCTAssertEqual(dto.toDomain().sport, .worldCup)
    }

    func testGameDTO_unknownSport_fallsBackToNFL() {
        let dto = makeGameDTO(sport: "unknown_sport")
        XCTAssertEqual(dto.toDomain().sport, .nfl)
    }

    func testGameDTO_withScores_mapsResultPosted() {
        let dto = makeGameDTO(homeScore: 27, awayScore: 14, resultPosted: true)
        let game = dto.toDomain()
        XCTAssertEqual(game.homeScore, 27)
        XCTAssertEqual(game.awayScore, 14)
        XCTAssertTrue(game.resultPosted)
    }

    // MARK: - PickDTO

    func testPickDTO_pendingResult() {
        XCTAssertEqual(makePickDTO(result: "pending").toDomain().result, .pending)
    }

    func testPickDTO_winResult() {
        XCTAssertEqual(makePickDTO(result: "win").toDomain().result, .win)
    }

    func testPickDTO_lossResult() {
        XCTAssertEqual(makePickDTO(result: "loss").toDomain().result, .loss)
    }

    func testPickDTO_superdogWinResult() {
        XCTAssertEqual(makePickDTO(result: "superdog_win").toDomain().result, .superdogWin)
    }

    func testPickDTO_unknownResult_fallsBackToPending() {
        XCTAssertEqual(makePickDTO(result: "garbage").toDomain().result, .pending)
    }

    func testPickDTO_isSuperdog_mapsCorrectly() {
        XCTAssertTrue(makePickDTO(isSuperdog: true).toDomain().isSuperdog)
        XCTAssertFalse(makePickDTO(isSuperdog: false).toDomain().isSuperdog)
    }

    // MARK: - StandingDTO

    func testStandingDTO_mapsToDomain() {
        let dto = StandingDTO(
            userID: "u1", groupID: "g1", displayName: "Alice",
            wins: 7, losses: 3, superdogWins: 1, superdogsUsed: 1,
            updatedAt: "2025-11-16T10:00:00Z"
        )
        let standing = dto.toDomain()
        XCTAssertEqual(standing.wins, 7)
        XCTAssertEqual(standing.losses, 3)
        XCTAssertEqual(standing.superdogWins, 1)
        XCTAssertEqual(standing.superdogsUsed, 1)
        XCTAssertEqual(standing.winPercentage, 0.7, accuracy: 0.001)
    }

    // MARK: - UserDTO

    func testUserDTO_mapsToDomain() {
        let dto = UserDTO(
            id: "u1", email: "alice@example.com", displayName: "Alice",
            fcmToken: "token-abc", createdAt: "2025-01-01T00:00:00Z"
        )
        let user = dto.toDomain()
        XCTAssertEqual(user.id, "u1")
        XCTAssertEqual(user.email, "alice@example.com")
        XCTAssertEqual(user.displayName, "Alice")
        XCTAssertEqual(user.fcmToken, "token-abc")
    }

    func testUserDTO_nilFcmToken_mapsToNil() {
        let dto = UserDTO(
            id: "u1", email: "alice@example.com", displayName: "Alice",
            fcmToken: nil, createdAt: "2025-01-01T00:00:00Z"
        )
        XCTAssertNil(dto.toDomain().fcmToken)
    }

    // MARK: - GroupDTO

    func testGroupDTO_seasonMode_mapsToDomain() {
        let dto = makeGroupDTO(sport: "americanfootball_nfl", mode: "season")
        let group = dto.toDomain()
        XCTAssertEqual(group.sport, .nfl)
        XCTAssertEqual(group.mode, .season)
    }

    func testGroupDTO_worldCupMode_mapsToDomain() {
        let dto = makeGroupDTO(sport: "soccer_fifa_world_cup", mode: "worldCup")
        let group = dto.toDomain()
        XCTAssertEqual(group.sport, .worldCup)
        XCTAssertEqual(group.mode, .worldCup)
    }

    func testGroupDTO_unknownSport_fallsBackToNFL() {
        let dto = makeGroupDTO(sport: "unknown_sport", mode: "season")
        XCTAssertEqual(dto.toDomain().sport, .nfl)
    }

    func testGroupDTO_unknownMode_fallsBackToSeason() {
        let dto = makeGroupDTO(sport: "americanfootball_nfl", mode: "unknown_mode")
        XCTAssertEqual(dto.toDomain().mode, .season)
    }

    func testGroupDTO_superdogsFields_map() {
        let dto = makeGroupDTO(superdogsEnabled: true, superdogsPerUser: 5)
        let group = dto.toDomain()
        XCTAssertTrue(group.superdogsEnabled)
        XCTAssertEqual(group.superdogsPerUser, 5)
    }

    // MARK: - Helpers

    private func makeGameDTO(
        sport: String = "americanfootball_nfl",
        homeScore: Int? = nil,
        awayScore: Int? = nil,
        resultPosted: Bool = false
    ) -> GameDTO {
        GameDTO(
            id: "g1", weekID: "w1", oddsAPIID: nil,
            sport: sport,
            homeTeam: "Home", awayTeam: "Away",
            spread: -3.5, favoriteTeam: "Home",
            kickoffAt: "2026-06-15T18:00:00Z",
            homeScore: homeScore, awayScore: awayScore,
            resultPosted: resultPosted
        )
    }

    private func makePickDTO(result: String = "pending", isSuperdog: Bool = false) -> PickDTO {
        PickDTO(
            id: "p1", userID: "u1", gameID: "g1", groupID: "grp1",
            pickedTeam: "Home", isSuperdog: isSuperdog,
            result: result,
            createdAt: "2026-06-15T10:00:00Z",
            updatedAt: "2026-06-15T10:00:00Z"
        )
    }

    private func makeGroupDTO(
        sport: String = "americanfootball_nfl",
        mode: String = "season",
        superdogsEnabled: Bool = false,
        superdogsPerUser: Int = 3
    ) -> GroupDTO {
        GroupDTO(
            id: "grp1", name: "Test Group", adminID: "u1", joinCode: "ABC123",
            sport: sport, mode: mode, seasonYear: 2026,
            blindPicks: false,
            superdogsEnabled: superdogsEnabled,
            superdogsPerUser: superdogsPerUser,
            createdAt: "2026-01-01T00:00:00Z"
        )
    }
}
