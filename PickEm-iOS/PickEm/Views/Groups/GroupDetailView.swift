import SwiftUI

struct GroupDetailView: View {
    private let group: Group
    @State private var slateViewModel: SlateViewModel
    @State private var pickViewModel: PickViewModel
    @State private var standingsViewModel: StandingsViewModel

    init(group: Group, dependencies: AppDependencies) {
        self.group = group
        let currentUserID = dependencies.authViewModel.currentUser?.id ?? MockData.currentUserID
        _slateViewModel = State(wrappedValue: SlateViewModel(
            group: group,
            gameRepository: dependencies.gameRepository,
            cacheService: dependencies.cacheService
        ))
        _pickViewModel = State(wrappedValue: PickViewModel(
            group: group,
            currentUserID: currentUserID,
            pickRepository: dependencies.pickRepository
        ))
        _standingsViewModel = State(wrappedValue: StandingsViewModel(
            group: group,
            standingsRepository: dependencies.standingsRepository,
            cacheService: dependencies.cacheService
        ))
    }

    var body: some View {
        TabView {
            SlateView(slateViewModel: slateViewModel, pickViewModel: pickViewModel)
                .tabItem { Label("Picks", systemImage: "checkmark.seal") }

            StandingsView(viewModel: standingsViewModel, currentUserID: pickViewModel.currentUserID)
                .tabItem { Label("Standings", systemImage: "trophy") }
        }
        .navigationTitle(group.name.uppercased())
        .navigationBarTitleDisplayMode(.inline)
        .peNavBar()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(
                    item: "Join \"\(group.name)\" on PickEm! Use code: \(group.joinCode)"
                ) {
                    Label("Invite", systemImage: "person.badge.plus")
                }
            }
        }
        .onLoad { await initialLoad() }
    }

    private func initialLoad() async {
        await slateViewModel.loadWeeks()
        if let week = slateViewModel.selectedWeek {
            await pickViewModel.loadPicks(weekID: week.id)
        }
        await standingsViewModel.loadStandings()
    }
}

#Preview {
    NavigationStack {
        GroupDetailView(group: MockData.group, dependencies: AppDependencies())
    }
}
