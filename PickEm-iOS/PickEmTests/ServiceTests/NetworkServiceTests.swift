import XCTest
@testable import PickEm

final class NetworkServiceTests: XCTestCase {
    private var sut: NetworkService!
    private var tokenStore: TokenStore!
    private let baseURL = URL(string: "https://test.example.com")!

    override func setUp() {
        super.setUp()
        tokenStore = TokenStore()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        sut = NetworkService(baseURL: baseURL, tokenStore: tokenStore, session: session)
        MockURLProtocol.requestHandler = nil
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        sut = nil
        tokenStore = nil
        super.tearDown()
    }

    // MARK: - Response status codes

    func testGet_200_decodesJSON() async throws {
        stub(statusCode: 200, json: #"{"value":"hello"}"#)
        let response: TestResponse = try await sut.get("/test")
        XCTAssertEqual(response.value, "hello")
    }

    func testGet_401_throwsUnauthorized() async {
        stub(statusCode: 401, json: "")
        await assertThrows(RepositoryError.unauthorized) {
            let _: TestResponse = try await self.sut.get("/test")
        }
    }

    func testGet_404_throwsNotFound() async {
        stub(statusCode: 404, json: "")
        await assertThrows(RepositoryError.notFound) {
            let _: TestResponse = try await self.sut.get("/test")
        }
    }

    func testGet_409_throwsConflictWithDetail() async {
        stub(statusCode: 409, json: #"{"detail":"Already exists"}"#)
        await assertThrowsConflict(expectedMessage: "Already exists") {
            let _: TestResponse = try await self.sut.get("/test")
        }
    }

    func testGet_409_noDetail_usesDefaultMessage() async {
        stub(statusCode: 409, json: "{}")
        await assertThrowsConflict(expectedMessage: "Conflict") {
            let _: TestResponse = try await self.sut.get("/test")
        }
    }

    func testGet_500_throwsServerError() async {
        stub(statusCode: 500, json: #"{"detail":"Internal error"}"#)
        await assertThrowsServerError(expectedCode: 500) {
            let _: TestResponse = try await self.sut.get("/test")
        }
    }

    func testGet_malformedJSON_throwsDecodingError() async {
        stub(statusCode: 200, json: "not-json")
        do {
            let _: TestResponse = try await sut.get("/test")
            XCTFail("Expected throw")
        } catch let error as RepositoryError {
            guard case .decodingError = error else {
                XCTFail("Expected .decodingError, got \(error)"); return
            }
        } catch {
            XCTFail("Expected .decodingError, got \(error)"); return
        }
    }

    // MARK: - Request headers

    func testGet_setsContentTypeHeader() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            return (self.makeHTTPResponse(statusCode: 200), Data(#"{"value":"x"}"#.utf8))
        }
        let _: TestResponse = try await sut.get("/test")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func testGet_noAuthHeader_whenTokenNotSet() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            return (self.makeHTTPResponse(statusCode: 200), Data(#"{"value":"x"}"#.utf8))
        }
        let _: TestResponse = try await sut.get("/test")
        XCTAssertNil(capturedRequest?.value(forHTTPHeaderField: "Authorization"))
    }

    func testGet_injectsAuthorizationHeader_whenTokenSet() async throws {
        tokenStore.save(accessToken: "my-token", refreshToken: "")
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            return (self.makeHTTPResponse(statusCode: 200), Data(#"{"value":"x"}"#.utf8))
        }
        let _: TestResponse = try await sut.get("/test")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer my-token")
    }

    func testPost_encodesBodyAsJSON() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            return (self.makeHTTPResponse(statusCode: 200), Data(#"{"value":"x"}"#.utf8))
        }
        let _: TestResponse = try await sut.post("/test", body: ["key": "val"])
        let request = try XCTUnwrap(capturedRequest)
        // URLSession converts httpBody → httpBodyStream before handing to URLProtocol
        let bodyData = try XCTUnwrap(readBodyData(from: request))
        let decoded = try JSONDecoder().decode([String: String].self, from: bodyData)
        XCTAssertEqual(decoded["key"], "val")
    }

    // MARK: - Helpers

    private func stub(statusCode: Int, json: String) {
        MockURLProtocol.requestHandler = { [weak self] _ in
            guard let self else { fatalError() }
            let response = self.makeHTTPResponse(statusCode: statusCode)
            return (response, Data(json.utf8))
        }
    }

    private func makeHTTPResponse(statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: baseURL, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
    }

    private func readBodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: 4096)
            if count > 0 { data.append(buffer, count: count) }
        }
        return data
    }

    private func assertThrows(_ expected: RepositoryError, operation: () async throws -> Void) async {
        do {
            try await operation()
            XCTFail("Expected throw of \(expected)")
        } catch let error as RepositoryError {
            guard error == expected else {
                XCTFail("Expected \(expected), got \(error)"); return
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    private func assertThrowsConflict(expectedMessage: String, operation: () async throws -> Void) async {
        do {
            try await operation()
            XCTFail("Expected conflict throw")
        } catch let error as RepositoryError {
            guard case .conflict(let msg) = error else {
                XCTFail("Expected .conflict, got \(error)"); return
            }
            XCTAssertEqual(msg, expectedMessage)
        }  catch {
            XCTFail("Expected .decodingError, got \(error)"); return
        }
    }

    private func assertThrowsServerError(expectedCode: Int, operation: () async throws -> Void) async {
        do {
            try await operation()
            XCTFail("Expected server error throw")
        } catch let error as RepositoryError {
            guard case .serverError(let code, _) = error else {
                XCTFail("Expected .serverError, got \(error)"); return
            }
            XCTAssertEqual(code, expectedCode)
        } catch {
            XCTFail("Expected .decodingError, got \(error)"); return
        }
    }
}

// MARK: - Test types

private struct TestResponse: Decodable {
    let value: String
}

// MARK: - URLProtocol stub

final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
