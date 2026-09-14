import XCTest
@testable import PickEm

@MainActor
final class AuthViewModelTests: XCTestCase {
    private var viewModel: AuthViewModel!

    override func setUp() {
        super.setUp()
        let tokenStore = TokenStore()
        tokenStore.clear() // wipe any leftover Keychain state from a prior test run
        viewModel = AuthViewModel(authRepository: MockAuthRepository(), tokenStore: tokenStore)
    }

    override func tearDown() {
        viewModel = nil
        TokenStore().clear()
        super.tearDown()
    }

    func testLogin_setsIsAuthenticated() async {
        XCTAssertFalse(viewModel.isAuthenticated)
        await viewModel.login(email: "alice@example.com", password: "password")
        XCTAssertTrue(viewModel.isAuthenticated)
        XCTAssertNil(viewModel.loginErrorMessage)
    }

    func testLogin_setsCurrentUser() async {
        await viewModel.login(email: "alice@example.com", password: "password")
        XCTAssertNotNil(viewModel.currentUser)
        XCTAssertEqual(viewModel.currentUser?.email, MockData.currentUser.email)
    }

    func testRegister_setsIsAuthenticated() async {
        await viewModel.register(email: "new@example.com", displayName: "New User", password: "pass123")
        XCTAssertTrue(viewModel.isAuthenticated)
        XCTAssertNil(viewModel.registerErrorMessage)
    }

    func testLogout_clearsState() async {
        await viewModel.login(email: "alice@example.com", password: "password")
        XCTAssertTrue(viewModel.isAuthenticated)
        await viewModel.logout()
        XCTAssertFalse(viewModel.isAuthenticated)
        XCTAssertNil(viewModel.currentUser)
    }
}
