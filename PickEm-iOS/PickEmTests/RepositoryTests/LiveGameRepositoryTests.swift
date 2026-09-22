import XCTest
import SwiftData
@testable import PickEm

@MainActor
final class LiveGameRepositoryTests: XCTestCase {
    private var sut: LiveGameRepository!
    private var cache: LocalCacheService!
    private let baseURL = URL(string: "https://test.example.com")!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        let tokenStore = TokenStore()
        tokenStore.clear()
        let network = NetworkService(baseURL: baseURL, tokenStore: tokenStore, session: session)

        let schema = Schema([CachedGame.self, CachedPick.self, CachedStanding.self])
        let modelConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: modelConfig)
        cache = LocalCacheService(container: container)

        sut = LiveGameRepository(network: network, cache: cache)
        MockURLProtocol.requestHandler = nil
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        sut = nil
        cache = nil
        super.tearDown()
    }

    private func stub(statusCode: Int, json: String) {
        MockURLProtocol.requestHandler = { [weak self] _ in
            guard let self else { fatalError() }
            let response = HTTPURLResponse(url: self.baseURL, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }
    }

    private let freshJSON = """
    [{"id":"game-1","week_id":"week-1","odds_api_id":"odds-1","sport":"americanfootball_nfl",
      "home_team":"Chiefs","away_team":"Raiders","spread":-3.5,"favorite_team":"Chiefs",
      "kickoff_at":"2026-09-22T00:00:00Z","home_score":31,"away_score":10,"result_posted":true}]
    """

    private var staleGame: Game {
        Game(
            id: "game-1", weekID: "week-1", oddsAPIID: "odds-1", sport: .nfl,
            homeTeam: "Chiefs", awayTeam: "Raiders", spread: -3.5, favoriteTeam: "Chiefs",
            kickoffAt: Date(timeIntervalSince1970: 0), homeScore: nil, awayScore: nil, resultPosted: false
        )
    }

    func testFetchGames_prefersFreshNetworkDataOverCache() async throws {
        cache.saveGames([staleGame], groupID: "g1", weekID: "week-1")
        stub(statusCode: 200, json: freshJSON)

        let result = try await sut.fetchGames(groupID: "g1", weekID: "week-1")

        XCTAssertEqual(result.first?.resultPosted, true)
        XCTAssertEqual(result.first?.homeScore, 31)
    }

    func testFetchGames_networkFailure_fallsBackToCache() async throws {
        cache.saveGames([staleGame], groupID: "g1", weekID: "week-1")
        stub(statusCode: 500, json: "")

        let result = try await sut.fetchGames(groupID: "g1", weekID: "week-1")

        XCTAssertEqual(result, [staleGame])
    }

    func testFetchGames_networkFailureNoCache_throws() async {
        stub(statusCode: 500, json: "")

        do {
            _ = try await sut.fetchGames(groupID: "g1", weekID: "week-1")
            XCTFail("Expected a throw")
        } catch {
            // expected — no cached fallback available
        }
    }
}
