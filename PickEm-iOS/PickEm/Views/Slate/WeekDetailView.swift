import SwiftUI
private typealias ViewGroup = SwiftUI.Group

struct WeekDetailView: View {
    let weekID: String
    var slateViewModel: SlateViewModel
    var pickViewModel: PickViewModel
    var standingsViewModel: StandingsViewModel
    @State private var pickTarget: Game?
    @State private var showManage = false

    private var weekGames: WeekGames? {
        slateViewModel.weekGames.first { $0.week.id == weekID }
    }

    private var displayNames: [String: String] {
        Dictionary(uniqueKeysWithValues: standingsViewModel.standings.map { ($0.userID, $0.displayName) })
    }

    var body: some View {
        ViewGroup {
            if let wg = weekGames {
                if wg.games.isEmpty {
                    emptyView
                } else {
                    gameList(wg.games)
                }
            } else {
                LoadingView(message: "Loading...")
            }
        }
        .navigationTitle(weekGames?.week.displayLabel ?? "Week")
        .navigationBarTitleDisplayMode(.inline)
        .peNavBar()
        .toolbar { adminToolbar }
        .refreshable {
            await slateViewModel.refresh()
            await pickViewModel.loadAllPicks(groupID: slateViewModel.group.id)
            await pickViewModel.loadAllMemberPicks(weekID: weekID)
        }
        .onLoad { await pickViewModel.loadAllMemberPicks(weekID: weekID) }
        .sheet(item: $pickTarget) { game in
            PickSubmissionView(
                game: game,
                group: slateViewModel.group,
                existingPick: pickViewModel.pick(for: game),
                pickViewModel: pickViewModel
            )
        }
        .sheet(isPresented: $showManage) {
            SlateManageView(viewModel: slateViewModel)
        }
    }

    // MARK: - Game list

    private func gameList(_ games: [Game]) -> some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(games) { game in
                    GameRowView(
                        game: game,
                        pick: pickViewModel.pick(for: game),
                        group: slateViewModel.group,
                        memberPicks: pickViewModel.memberPicks(for: game).map {
                            MemberPickDisplay(pick: $0, displayName: displayNames[$0.userID] ?? "Member")
                        },
                        onPickTapped: { pickTarget = game }
                    )
                    .padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 16)
        }
        .background(AdaptiveColor.peBackground)
    }

    // MARK: - Empty state

    @ViewBuilder
    private var emptyView: some View {
        if slateViewModel.isAdmin {
            ContentUnavailableView {
                Label("No Games Yet", systemImage: "calendar.badge.plus")
            } description: {
                Text("Tap ⚙️ to add games from this week's schedule.")
            } actions: {
                Button("Add Games") {
                    if let week = weekGames?.week {
                        slateViewModel.selectedWeek = week
                    }
                    showManage = true
                }
                .buttonStyle(.borderedProminent)
            }
        } else {
            ContentUnavailableView(
                "No Games Yet",
                systemImage: "calendar.badge.exclamationmark",
                description: Text("Your commissioner is still setting up this week's games.")
            )
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var adminToolbar: some ToolbarContent {
        if slateViewModel.isAdmin {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if let week = weekGames?.week {
                        slateViewModel.selectedWeek = week
                    }
                    showManage = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        WeekDetailView(
            weekID: MockData.nflWeek.id,
            slateViewModel: SlateViewModel(
                group: MockData.group,
                gameRepository: MockGameRepository()
            ),
            pickViewModel: PickViewModel(
                group: MockData.group,
                currentUserID: MockData.currentUserID,
                pickRepository: MockPickRepository()
            ),
            standingsViewModel: StandingsViewModel(
                group: MockData.group,
                standingsRepository: MockStandingsRepository()
            )
        )
    }
}
