import XCTest
import SwiftData
@testable import PickEm

@MainActor
final class LocalCacheServiceTests: XCTestCase {
    private var sut: LocalCacheService!
    private var context: ModelContext { sut.context }

    override func setUp() async throws {
        try await super.setUp()
        let schema = Schema([CachedGame.self, CachedPick.self, CachedStanding.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: config)
        sut = LocalCacheService(container: container)
    }

    override func tearDown() async throws {
        sut = nil
        try await super.tearDown()
    }

    // MARK: - Slate scope

    func testInvalidate_slateScope_deletesMatchingGames() throws {
        insertGame(id: "g1", weekID: "wk1", groupID: "grp1")
        insertGame(id: "g2", weekID: "wk1", groupID: "grp1")
        try context.save()

        sut.invalidate(scope: .slate(groupID: "grp1", weekID: "wk1"))

        XCTAssertEqual(try fetchGames().count, 0)
    }

    func testInvalidate_slateScope_keepsDifferentWeek() throws {
        insertGame(id: "g1", weekID: "wk1", groupID: "grp1")
        insertGame(id: "g2", weekID: "wk2", groupID: "grp1")
        try context.save()

        sut.invalidate(scope: .slate(groupID: "grp1", weekID: "wk1"))

        let remaining = try fetchGames()
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.weekID, "wk2")
    }

    func testInvalidate_slateScope_keepsDifferentGroup() throws {
        insertGame(id: "g1", weekID: "wk1", groupID: "grp1")
        insertGame(id: "g2", weekID: "wk1", groupID: "grp2")
        try context.save()

        sut.invalidate(scope: .slate(groupID: "grp1", weekID: "wk1"))

        let remaining = try fetchGames()
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.groupID, "grp2")
    }

    // MARK: - Standings scope

    func testInvalidate_standingsScope_deletesMatchingStandings() throws {
        insertStanding(id: "s1", groupID: "grp1")
        insertStanding(id: "s2", groupID: "grp1")
        try context.save()

        sut.invalidate(scope: .standings(groupID: "grp1"))

        XCTAssertEqual(try fetchStandings().count, 0)
    }

    func testInvalidate_standingsScope_keepsDifferentGroup() throws {
        insertStanding(id: "s1", groupID: "grp1")
        insertStanding(id: "s2", groupID: "grp2")
        try context.save()

        sut.invalidate(scope: .standings(groupID: "grp1"))

        let remaining = try fetchStandings()
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.groupID, "grp2")
    }

    // MARK: - All scope

    func testInvalidate_allScope_deletesAllModels() throws {
        insertGame(id: "g1", weekID: "wk1", groupID: "grp1")
        insertPick(id: "p1", gameID: "g1", groupID: "grp1", weekID: "wk1")
        insertStanding(id: "s1", groupID: "grp1")
        try context.save()

        sut.invalidate(scope: .all)

        XCTAssertEqual(try fetchGames().count, 0)
        XCTAssertEqual(try fetchPicks().count, 0)
        XCTAssertEqual(try fetchStandings().count, 0)
    }

    // MARK: - Results scope

    func testInvalidate_resultsScope_deletesGamesAndStandingsForGroup() throws {
        insertGame(id: "g1", weekID: "wk1", groupID: "grp1")
        insertGame(id: "g2", weekID: "wk1", groupID: "grp2")
        insertStanding(id: "s1", groupID: "grp1")
        insertStanding(id: "s2", groupID: "grp2")
        try context.save()

        sut.invalidate(scope: .results(groupID: "grp1"))

        let games = try fetchGames()
        XCTAssertEqual(games.count, 1)
        XCTAssertEqual(games.first?.groupID, "grp2")

        let standings = try fetchStandings()
        XCTAssertEqual(standings.count, 1)
        XCTAssertEqual(standings.first?.groupID, "grp2")
    }

    func testInvalidate_resultsScope_doesNotDeletePicks() throws {
        insertPick(id: "p1", gameID: "g1", groupID: "grp1", weekID: "wk1")
        try context.save()

        sut.invalidate(scope: .results(groupID: "grp1"))

        XCTAssertEqual(try fetchPicks().count, 1)
    }

    // MARK: - Insert helpers

    private func insertGame(id: String, weekID: String, groupID: String) {
        context.insert(CachedGame(id: id, weekID: weekID, groupID: groupID, data: Data()))
    }

    private func insertPick(id: String, gameID: String, groupID: String, weekID: String) {
        context.insert(CachedPick(id: id, gameID: gameID, groupID: groupID, weekID: weekID, data: Data()))
    }

    private func insertStanding(id: String, groupID: String) {
        context.insert(CachedStanding(id: id, groupID: groupID, data: Data()))
    }

    // MARK: - Fetch helpers

    private func fetchGames() throws -> [CachedGame] {
        try context.fetch(FetchDescriptor<CachedGame>())
    }

    private func fetchPicks() throws -> [CachedPick] {
        try context.fetch(FetchDescriptor<CachedPick>())
    }

    private func fetchStandings() throws -> [CachedStanding] {
        try context.fetch(FetchDescriptor<CachedStanding>())
    }
}
