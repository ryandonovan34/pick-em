import XCTest
import SwiftData
@testable import PickEm

@MainActor
final class LiveStandingsRepositoryTests: XCTestCase {
    private var sut: LiveStandingsRepository!
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

        sut = LiveStandingsRepository(network: network, cache: cache)
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
    [{"user_id":"u1","group_id":"g1","display_name":"Fresh","wins":9,"losses":1,"superdog_wins":2,"superdogs_used":3,"updated_at":"2026-09-22T00:00:00Z"}]
    """

    private var staleStanding: Standing {
        Standing(userID: "u1", groupID: "g1", displayName: "Stale", wins: 0, losses: 0, superdogWins: 0, superdogsUsed: 0, updatedAt: Date(timeIntervalSince1970: 0))
    }

    func testFetchStandings_prefersFreshNetworkDataOverCache() async throws {
        cache.saveStandings([staleStanding], groupID: "g1")
        stub(statusCode: 200, json: freshJSON)

        let result = try await sut.fetchStandings(groupID: "g1")

        XCTAssertEqual(result.first?.displayName, "Fresh")
        XCTAssertEqual(result.first?.wins, 9)
    }

    func testFetchStandings_networkFailure_fallsBackToCache() async throws {
        cache.saveStandings([staleStanding], groupID: "g1")
        stub(statusCode: 500, json: "")

        let result = try await sut.fetchStandings(groupID: "g1")

        XCTAssertEqual(result, [staleStanding])
    }

    func testFetchStandings_networkFailureNoCache_throws() async {
        stub(statusCode: 500, json: "")

        do {
            _ = try await sut.fetchStandings(groupID: "g1")
            XCTFail("Expected a throw")
        } catch {
            // expected — no cached fallback available
        }
    }
}
