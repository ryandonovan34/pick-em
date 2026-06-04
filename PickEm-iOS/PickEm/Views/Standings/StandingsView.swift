import SwiftUI
private typealias ViewGroup = SwiftUI.Group

struct StandingsView: View {
    var viewModel: StandingsViewModel
    let currentUserID: String

    @Environment(\.colorScheme) private var colorScheme

    private var separatorColor: Color {
        colorScheme == .dark ? Color(hex: "3c494e") : Color(hex: "bac9cc")
    }

    var body: some View {
        ViewGroup {
            if viewModel.isLoading && viewModel.standings.isEmpty {
                LoadingView(message: "Loading standings...")
            } else if let error = viewModel.errorMessage, viewModel.standings.isEmpty {
                ErrorView(message: error) {
                    Task { await viewModel.loadStandings() }
                }
            } else if viewModel.standings.isEmpty {
                ContentUnavailableView(
                    "No Standings Yet",
                    systemImage: "trophy",
                    description: Text("Standings will appear after the first results are posted.")
                )
            } else {
                standingsList
            }
        }
        .navigationTitle("Leaderboard")
        .peNavBar()
        .refreshable { await viewModel.refresh() }
    }

    private var standingsList: some View {
        let rows = viewModel.standings
        return List {
            ForEach(rows.indices, id: \.self) { index in
                let standing = rows[index]
                StandingRow(
                    rank: index + 1,
                    standing: standing,
                    isCurrentUser: standing.userID == currentUserID,
                    superdogsEnabled: viewModel.group.superdogsEnabled,
                    superdogsPerUser: viewModel.group.superdogsPerUser
                )
            }
        }
        .listStyle(.automatic)
        .scrollContentBackground(.hidden)
        .background(AdaptiveColor.peBackground)
    }
}

private struct StandingRow: View {
    let rank: Int
    let standing: Standing
    let isCurrentUser: Bool
    let superdogsEnabled: Bool
    let superdogsPerUser: Int

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.peScore())
                .foregroundStyle(rankColor)
                .frame(width: 36, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(standing.displayName.uppercased())
                        .font(.peHeadlineMd())
                        .foregroundStyle(AdaptiveColor.peOnSurface)
                    if isCurrentUser {
                        Text("YOU")
                            .font(.peLabelBold())
                            .tracking(1)
                            .foregroundStyle(AdaptiveColor.pePrimaryFill)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .overlay(
                                RoundedRectangle(cornerRadius: 2)
                                    .stroke(AdaptiveColor.pePrimaryFill, lineWidth: 1)
                            )
                    }
                }
                if superdogsEnabled {
                    Text("\(superdogsPerUser - standing.superdogsUsed) superdogs remaining")
                        .font(.peLabelSm())
                        .foregroundStyle(AdaptiveColor.peOnSurfaceVar)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(standing.record)
                    .font(.peScore())
                    .foregroundStyle(AdaptiveColor.peOnSurface)
                Text(String(format: "%.1f%%", standing.winPercentage * 100))
                    .font(.peLabelSm())
                    .foregroundStyle(AdaptiveColor.peOnSurfaceVar)
            }
        }
        .padding(.vertical, 4)
    }

    // Explicit AnyShapeStyle return type — avoids type-checker issues on switch expressions
    private var rankColor: AnyShapeStyle {
        switch rank {
        case 1:  AnyShapeStyle(Color(hex: "FFD700"))
        case 2:  AnyShapeStyle(AdaptiveColor.peOnSurfaceVar)
        case 3:  AnyShapeStyle(Color(hex: "CD7F32"))
        default: AnyShapeStyle(AdaptiveColor.peOutline)
        }
    }
}

#Preview {
    NavigationStack {
        StandingsView(
            viewModel: StandingsViewModel(
                group: MockData.group,
                standingsRepository: MockStandingsRepository()
            ),
            currentUserID: MockData.currentUserID
        )
    }
}
