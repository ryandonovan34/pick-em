import SwiftUI

struct GroupDetailView: View {
    private let group: Group
    var groupViewModel: GroupViewModel
    @State private var slateViewModel: SlateViewModel
    @State private var pickViewModel: PickViewModel
    @State private var standingsViewModel: StandingsViewModel
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirmation = false
    @State private var showLeaveConfirmation = false

    private var currentUserID: String {
        dependencies.authViewModel.currentUser?.id ?? ""
    }

    private var isAdmin: Bool {
        group.adminID == currentUserID
    }

    init(group: Group, groupViewModel: GroupViewModel, dependencies: AppDependencies) {
        self.group = group
        self.groupViewModel = groupViewModel
        let currentUserID = dependencies.authViewModel.currentUser?.id ?? ""
        _slateViewModel = State(wrappedValue: SlateViewModel(
            group: group,
            gameRepository: dependencies.gameRepository,
            cacheService: dependencies.cacheService,
            currentUserID: currentUserID
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
        VStack(spacing: 0) {
            JoinCodeBanner(group: group)

            TabView {
                SlateView(slateViewModel: slateViewModel, pickViewModel: pickViewModel)
                    .tabItem { Label("Weeks", systemImage: "calendar") }

                StandingsView(
                    viewModel: standingsViewModel,
                    slateViewModel: slateViewModel,
                    pickViewModel: pickViewModel,
                    currentUserID: pickViewModel.currentUserID
                )
                    .tabItem { Label("Standings", systemImage: "trophy") }
            }
        }
        .navigationDestination(for: Week.self) { week in
            WeekDetailView(
                weekID: week.id,
                slateViewModel: slateViewModel,
                pickViewModel: pickViewModel,
                standingsViewModel: standingsViewModel
            )
        }
        .navigationDestination(for: Standing.self) { standing in
            PlayerHistoryView(
                viewModel: PlayerHistoryViewModel(
                    group: group,
                    userID: standing.userID,
                    displayName: standing.displayName,
                    pickRepository: dependencies.pickRepository
                )
            )
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
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if isAdmin {
                        Button("Delete Group", systemImage: "trash", role: .destructive) {
                            showDeleteConfirmation = true
                        }
                    } else {
                        Button("Leave Group", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                            showLeaveConfirmation = true
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(AdaptiveColor.pePrimary)
                }
            }
        }
        .confirmationDialog(
            "Delete \"\(group.name)\"?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Group", role: .destructive) {
                Task {
                    if await groupViewModel.deleteGroup(groupID: group.id) {
                        dismiss()
                    }
                }
            }
        } message: {
            Text("This permanently deletes the group, its weeks, picks, and standings for every member. This can't be undone.")
        }
        .confirmationDialog(
            "Leave \"\(group.name)\"?",
            isPresented: $showLeaveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Leave Group", role: .destructive) {
                Task {
                    if await groupViewModel.leaveGroup(groupID: group.id) {
                        dismiss()
                    }
                }
            }
        } message: {
            Text("You'll need the join code to rejoin later.")
        }
        .onLoad { await initialLoad() }
        .onChange(of: dependencies.authViewModel.currentUser) { _, user in
            if let id = user?.id {
                slateViewModel.currentUserID = id
                pickViewModel.currentUserID = id
            }
        }
    }

    private func initialLoad() async {
        await slateViewModel.loadWeeks()
        await pickViewModel.loadAllPicks(groupID: group.id)
        await standingsViewModel.loadStandings()
    }
}

private struct JoinCodeBanner: View {
    let group: Group
    @State private var copied = false

    var body: some View {
        Button(action: copyCode) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("JOIN CODE")
                        .font(.peLabelSm())
                        .foregroundStyle(AdaptiveColor.peOnSurfaceVar)
                        .tracking(1)
                    Text(group.joinCode)
                        .font(.system(size: 16, weight: .heavy, design: .monospaced).width(.condensed))
                        .foregroundStyle(AdaptiveColor.pePrimary)
                        .tracking(4)
                }

                Spacer()

                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(copied ? AdaptiveColor.peSecondary : AdaptiveColor.pePrimary)
                    .contentTransition(.symbolEffect(.replace))
                    .animation(.spring(duration: 0.3), value: copied)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(AdaptiveColor.peSurface)
        }
        .buttonStyle(.plain)
    }

    private func copyCode() {
        UIPasteboard.general.string = group.joinCode
        guard !copied else { return }
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }
}

#Preview {
    NavigationStack {
        GroupDetailView(
            group: MockData.group,
            groupViewModel: GroupViewModel(groupRepository: MockGroupRepository()),
            dependencies: AppDependencies()
        )
    }
}
