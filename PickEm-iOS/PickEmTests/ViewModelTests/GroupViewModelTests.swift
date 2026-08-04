import XCTest
@testable import PickEm

@MainActor
final class GroupViewModelTests: XCTestCase {
    private var viewModel: GroupViewModel!

    override func setUp() {
        super.setUp()
        viewModel = GroupViewModel(groupRepository: MockGroupRepository())
    }

    func testLoadGroups_populatesGroups() async {
        await viewModel.loadGroups()
        XCTAssertFalse(viewModel.groups.isEmpty)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testCreateGroup_addsToList() async {
        await viewModel.loadGroups()
        let initialCount = viewModel.groups.count
        let group = await viewModel.createGroup(
            name: "Test Group", sport: .nfl, mode: .season,
            seasonYear: 2025, blindPicks: true,
            superdogsEnabled: false, superdogsPerUser: 3,
            includePreseason: false, includePlayoffs: true
        )
        XCTAssertNotNil(group)
        XCTAssertEqual(viewModel.groups.count, initialCount + 1)
    }

    func testJoinGroup_withValidCode_succeeds() async {
        let group = await viewModel.joinGroup(joinCode: MockData.group.joinCode)
        XCTAssertNotNil(group)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testJoinGroup_withInvalidCode_setsError() async {
        let group = await viewModel.joinGroup(joinCode: "NOPE00")
        XCTAssertNil(group)
        XCTAssertNotNil(viewModel.errorMessage)
    }
}
