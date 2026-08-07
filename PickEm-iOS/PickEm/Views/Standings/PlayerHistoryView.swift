import SwiftUI

struct PlayerHistoryView: View {
    var viewModel: PlayerHistoryViewModel

    var body: some View {
        SwiftUI.Group {
            if viewModel.isLoading && viewModel.entries.isEmpty {
                LoadingView(message: "Loading history...")
            } else if let error = viewModel.errorMessage, viewModel.entries.isEmpty {
                ErrorView(message: error) {
                    Task { await viewModel.loadHistory() }
                }
            } else if viewModel.entries.isEmpty {
                ContentUnavailableView(
                    "No Graded Picks Yet",
                    systemImage: "list.bullet.clipboard",
                    description: Text("\(viewModel.displayName)'s picks will appear here once results are posted.")
                )
            } else {
                historyList
            }
        }
        .navigationTitle(viewModel.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .peNavBar()
        .refreshable { await viewModel.loadHistory() }
        .onLoad { await viewModel.loadHistory() }
    }

    private var historyList: some View {
        List {
            Section {
                HStack {
                    Text("RECORD")
                        .font(.peLabelSm())
                        .tracking(1)
                        .foregroundStyle(AdaptiveColor.peOnSurfaceVar)
                    Spacer()
                    Text(viewModel.rows.last?.recordAfter ?? "0-0")
                        .font(.peHeadlineLg())
                        .foregroundStyle(AdaptiveColor.peOnSurface)
                }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            ForEach(viewModel.rows) { row in
                PlayerHistoryRowView(row: row)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AdaptiveColor.peBackground)
    }
}

private struct PlayerHistoryRowView: View {
    let row: PlayerHistoryRow

    private var entry: PickHistoryEntry { row.entry }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(accentColor)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(entry.weekLabel.uppercased())
                        .font(.peLabelSm())
                        .tracking(1)
                        .foregroundStyle(AdaptiveColor.peOnSurfaceVar)
                    Spacer()
                    Text(entry.kickoffAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.peLabelSm())
                        .foregroundStyle(AdaptiveColor.peOnSurfaceVar)
                }

                Text("\(TeamInfo.from(entry.awayTeam).acronym) @ \(TeamInfo.from(entry.homeTeam).acronym)")
                    .font(.peHeadlineMd())
                    .foregroundStyle(AdaptiveColor.peOnSurface)

                if let home = entry.homeScore, let away = entry.awayScore {
                    Text("Final \(TeamInfo.from(entry.awayTeam).acronym) \(away) – \(home) \(TeamInfo.from(entry.homeTeam).acronym)")
                        .font(.peLabelSm())
                        .foregroundStyle(AdaptiveColor.peOnSurfaceVar)
                }

                HStack(spacing: 6) {
                    Image(systemName: resultIcon)
                        .font(.caption.bold())
                    Text(pickedLabel)
                        .font(.peLabelBold())
                    Spacer()
                    Text(row.recordAfter)
                        .font(.peLabelBold())
                        .foregroundStyle(AdaptiveColor.peOnSurfaceVar)
                }
                .foregroundStyle(resultColor)
            }
            .padding(14)
        }
        .background(AdaptiveColor.peSurfaceLow)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AdaptiveColor.peOutlineVar, lineWidth: 1)
        )
    }

    private var pickedLabel: String {
        if entry.isForfeit { return "Missed Pick" }
        let favoriteTag = entry.pickedFavorite ? "Favorite" : "Underdog"
        let superdogTag = entry.isSuperdog ? " ★ Superdog" : ""
        return "\(entry.pickedTeam) (\(favoriteTag))\(superdogTag)"
    }

    private var resultIcon: String {
        if entry.isForfeit { return "exclamationmark.circle.fill" }
        switch entry.result {
        case .win, .superdogWin: return "trophy.fill"
        case .loss:              return "xmark.circle.fill"
        case .pending:           return "clock.fill"
        }
    }

    private var accentColor: Color {
        switch entry.result {
        case .win, .superdogWin: return .peLimeFill
        case .loss:              return Color(hex: "ffb4ab")
        case .pending:           return Color(hex: "00d1ff")
        }
    }

    private var resultColor: AnyShapeStyle {
        switch entry.result {
        case .win, .superdogWin: AnyShapeStyle(AdaptiveColor.peSecondary)
        case .loss:              AnyShapeStyle(AdaptiveColor.peError)
        case .pending:           AnyShapeStyle(AdaptiveColor.pePrimary)
        }
    }
}

#Preview {
    NavigationStack {
        PlayerHistoryView(
            viewModel: PlayerHistoryViewModel(
                group: MockData.group,
                userID: MockData.currentUserID,
                displayName: "Alice",
                pickRepository: MockPickRepository()
            )
        )
    }
}
