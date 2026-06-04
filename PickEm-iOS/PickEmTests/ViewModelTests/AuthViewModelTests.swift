import XCTest
@testable import PickEm

@MainActor
final class AuthViewModelTests: XCTestCase {
    private var viewModel: AuthViewModel!

    override func setUp() {
        super.setUp()
        viewModel = AuthViewModel(authRepository: MockAuthRepository(), tokenStore: TokenStore())
    }

    func testLogin_setsIsAuthenticated() async {
        XCTAssertFalse(viewModel.isAuthenticated)
        await viewModel.login(email: "alice@example.com", password: "password")
        XCTAssertTrue(viewModel.isAuthenticated)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testLogin_setsCurrentUser() async {
        await viewModel.login(email: "alice@example.com", password: "password")
        XCTAssertNotNil(viewModel.currentUser)
        XCTAssertEqual(viewModel.currentUser?.email, MockData.currentUser.email)
    }

    func testRegister_setsIsAuthenticated() async {
        await viewModel.register(email: "new@example.com", displayName: "New User", password: "pass123")
        XCTAssertTrue(viewModel.isAuthenticated)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testLogout_clearsState() async {
        await viewModel.login(email: "alice@example.com", password: "password")
        XCTAssertTrue(viewModel.isAuthenticated)
        await viewModel.logout()
        XCTAssertFalse(viewModel.isAuthenticated)
        XCTAssertNil(viewModel.currentUser)
    }
}
