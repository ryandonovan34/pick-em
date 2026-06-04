import SwiftUI
private typealias ViewGroup = SwiftUI.Group

struct SlateView: View {
    var slateViewModel: SlateViewModel
    var pickViewModel: PickViewModel
    @State private var pickTarget: Game?

    var body: some View {
        ViewGroup {
            if slateViewModel.isLoading && slateViewModel.games.isEmpty {
                LoadingView(message: "Loading games...")
            } else if let error = slateViewModel.errorMessage, slateViewModel.games.isEmpty {
                ErrorView(message: error) {
                    Task { await slateViewModel.refresh() }
                }
            } else {
                gameList
            }
        }
        .navigationTitle(slateViewModel.selectedWeek?.label ?? "Slate")
        .toolbar {
            if slateViewModel.weeks.count > 1 {
                ToolbarItem(placement: .navigationBarLeading) {
                    weekPicker
                }
            }
        }
        .peNavBar()
        .refreshable {
            await slateViewModel.refresh()
            if let week = slateViewModel.selectedWeek {
                await pickViewModel.loadPicks(weekID: week.id)
            }
        }
        .sheet(item: $pickTarget) { game in
            PickSubmissionView(
                game: game,
                group: slateViewModel.group,
                existingPick: pickViewModel.pick(for: game),
                pickViewModel: pickViewModel
            )
        }
    }

    private var gameList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(slateViewModel.games) { game in
                    GameRowView(
                        game: game,
                        pick: pickViewModel.pick(for: game),
                        group: slateViewModel.group,
                        onPickTapped: { pickTarget = game }
                    )
                    .padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 16)
        }
        .background(AdaptiveColor.peBackground)
    }

    private var weekPicker: some View {
        Menu {
            ForEach(slateViewModel.weeks) { week in
                Button(week.label) {
                    Task { await slateViewModel.selectWeek(week) }
                }
            }
        } label: {
            Label(slateViewModel.selectedWeek?.label ?? "Week", systemImage: "calendar")
                .font(.peLabelSm())
                .foregroundStyle(AdaptiveColor.pePrimary)
        }
    }
}

#Preview {
    NavigationStack {
        SlateView(
            slateViewModel: SlateViewModel(
                group: MockData.group,
                gameRepository: MockGameRepository()
            ),
            pickViewModel: PickViewModel(
                group: MockData.group,
                currentUserID: MockData.currentUserID,
                pickRepository: MockPickRepository()
            )
        )
    }
}
