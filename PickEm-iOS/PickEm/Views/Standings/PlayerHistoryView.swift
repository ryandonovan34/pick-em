import SwiftUI

struct PlayerHistoryView: View {
    @State private var viewModel: PlayerHistoryViewModel
    @State private var entryToSet: PickHistoryEntry?

    /// Owns its view model via @State rather than receiving an
    /// already-constructed instance, so the model's identity survives
    /// however many times SwiftUI re-invokes the enclosing
    /// navigationDestination(for:) closure — a plain `var` property was
    /// getting silently replaced by a fresh, still-empty instance after the
    /// original one had already finished loading, discarding the fetched
    /// data on screen while `.onLoad`'s once-only guard prevented refetching.
    init(
        group: Group,
        userID: String,
        displayName: String,
        currentUserID: String,
        pickRepository: any PickRepositoryProtocol,
        onMissedPickSet: @escaping () async -> Void = {}
    ) {
        _viewModel = State(wrappedValue: PlayerHistoryViewModel(
            group: group,
            userID: userID,
            displayName: displayName,
            currentUserID: currentUserID,
            pickRepository: pickRepository,
            onMissedPickSet: onMissedPickSet
        ))
    }

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
        .confirmationDialog(
            "Set \(viewModel.displayName)'s Pick",
            isPresented: Binding(get: { entryToSet != nil }, set: { if !$0 { entryToSet = nil } }),
            titleVisibility: .visible,
            presenting: entryToSet
        ) { entry in
            ForEach([entry.awayTeam, entry.homeTeam], id: \.self) { team in
                Button(entry.spreadLabel(for: team)) {
                    Task { await viewModel.setMissedPick(entry, pickedTeam: team) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This is graded against the final score and updates the standings right away. It can't be changed afterward.")
        }
        .alert(
            "Couldn't Set Pick",
            isPresented: Binding(
                get: { viewModel.missedPickErrorMessage != nil },
                set: { if !$0 { viewModel.missedPickErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.missedPickErrorMessage ?? "")
        }
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
                PlayerHistoryRowView(
                    row: row,
                    isSettingPick: viewModel.isSettingMissedPick,
                    onSetPick: viewModel.canSetMissedPicks && row.entry.isForfeit ? { entryToSet = row.entry } : nil
                )
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
    let isSettingPick: Bool
    let onSetPick: (() -> Void)?

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

                if let onSetPick {
                    Button("SET PICK", action: onSetPick)
                        .font(.peLabelBold())
                        .tracking(1)
                        .foregroundStyle(AdaptiveColor.pePrimary)
                        .buttonStyle(.borderless)
                        .disabled(isSettingPick)
                }
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
            group: MockData.group,
            userID: MockData.currentUserID,
            displayName: "Alice",
            currentUserID: MockData.currentUserID,
            pickRepository: MockPickRepository()
        )
    }
}
