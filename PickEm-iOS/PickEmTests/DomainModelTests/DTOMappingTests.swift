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
            kickoffAt: Date(),
            homeScore: nil, awayScore: nil, resultPosted: false
        )
        let game = dto.toDomain()
        XCTAssertEqual(game.id, "g1")
        XCTAssertEqual(game.sport, .nfl)
        XCTAssertEqual(game.spread, -7.5)
        XCTAssertFalse(game.resultPosted)
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

    func testPickDTO_isForfeit_mapsCorrectly() {
        XCTAssertTrue(makePickDTO(isForfeit: true).toDomain().isForfeit)
        XCTAssertFalse(makePickDTO(isForfeit: false).toDomain().isForfeit)
    }

    // MARK: - PickHistoryEntryDTO

    func testPickHistoryEntryDTO_mapsToDomain() {
        let dto = PickHistoryEntryDTO(
            pickID: "p1", gameID: "g1", weekNumber: 9, weekLabel: "Week 9",
            homeTeam: "Kansas City Chiefs", awayTeam: "Las Vegas Raiders",
            pickedTeam: "Kansas City Chiefs", favoriteTeam: "Kansas City Chiefs",
            spread: -7.5, kickoffAt: Date(),
            isSuperdog: false, isForfeit: false, result: "win",
            homeScore: 27, awayScore: 14
        )
        let entry = dto.toDomain()
        XCTAssertEqual(entry.pickID, "p1")
        XCTAssertEqual(entry.weekLabel, "Week 9")
        XCTAssertEqual(entry.result, .win)
        XCTAssertTrue(entry.pickedFavorite)
        XCTAssertEqual(entry.underdogTeam, "Las Vegas Raiders")
    }

    func testPickHistoryEntryDTO_unknownResult_fallsBackToPending() {
        let dto = PickHistoryEntryDTO(
            pickID: "p1", gameID: "g1", weekNumber: 9, weekLabel: "Week 9",
            homeTeam: "Kansas City Chiefs", awayTeam: "Las Vegas Raiders",
            pickedTeam: "Las Vegas Raiders", favoriteTeam: "Kansas City Chiefs",
            spread: -7.5, kickoffAt: Date(),
            isSuperdog: true, isForfeit: false, result: "garbage",
            homeScore: nil, awayScore: nil
        )
        let entry = dto.toDomain()
        XCTAssertEqual(entry.result, .pending)
        XCTAssertFalse(entry.pickedFavorite)
    }

    // MARK: - StandingDTO

    func testStandingDTO_mapsToDomain() {
        let dto = StandingDTO(
            userID: "u1", groupID: "g1", displayName: "Alice",
            wins: 7, losses: 3, superdogWins: 1, superdogsUsed: 1,
            updatedAt: Date()
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
            fcmToken: "token-abc", createdAt: Date()
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
            fcmToken: nil, createdAt: Date()
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
            kickoffAt: Date(),
            homeScore: homeScore, awayScore: awayScore,
            resultPosted: resultPosted
        )
    }

    private func makePickDTO(result: String = "pending", isSuperdog: Bool = false, isForfeit: Bool = false) -> PickDTO {
        PickDTO(
            id: "p1", userID: "u1", gameID: "g1", groupID: "grp1",
            pickedTeam: "Home", isSuperdog: isSuperdog,
            result: result,
            isForfeit: isForfeit,
            createdAt: Date(),
            updatedAt: Date()
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
            includePreseason: false,
            includePlayoffs: true,
            createdAt: Date()
        )
    }
}
