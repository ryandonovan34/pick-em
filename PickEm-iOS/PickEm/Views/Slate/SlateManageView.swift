import SwiftUI

struct SlateManageView: View {
    @Environment(\.dismiss) private var dismiss
    var viewModel: SlateViewModel
    @State private var alertError: String?

    private var week: Week? { viewModel.selectedWeek }

    var body: some View {
        NavigationStack {
            List {
                if let week {
                    currentSlateSection(week: week)
                    availableGamesSection(week: week)
                }
            }
            .navigationTitle("Manage Week")
            .navigationBarTitleDisplayMode(.inline)
            .peNavBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Error", isPresented: Binding(
                get: { alertError != nil },
                set: { if !$0 { alertError = nil } }
            )) {
                Button("OK") { alertError = nil }
            } message: {
                Text(alertError ?? "")
            }
        }
        .task {
            if let week { await viewModel.fetchAvailableOdds(for: week) }
        }
    }

    // MARK: - Current slate

    private func currentSlateSection(week: Week) -> some View {
        Section("In This Week (\(viewModel.games.count))") {
            if viewModel.isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Loading…").foregroundStyle(.secondary)
                }
            } else if viewModel.games.isEmpty {
                Text("No games yet — add some below")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                if viewModel.games.contains(where: { $0.isLocked }) {
                    Label("Some games have kicked off and are locked", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(viewModel.games) { game in
                    ManageGameRow(game: game, isAdding: false, isLocked: game.isLocked) {
                        Task {
                            do {
                                try await viewModel.removeGame(game, from: week)
                            } catch {
                                alertError = error.localizedDescription
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Available games

    private func availableGamesSection(week: Week) -> some View {
        Section("Available to Add (\(viewModel.availableGames.count))") {
            if viewModel.availableGames.isEmpty {
                Text("No additional games in the pool for this week")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(viewModel.availableGames) { game in
                    ManageGameRow(game: game, isAdding: true) {
                        Task {
                            do {
                                try await viewModel.addGame(game, to: week)
                            } catch {
                                alertError = error.localizedDescription
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Game row

private struct ManageGameRow: View {
    let game: Game
    let isAdding: Bool
    var isLocked: Bool = false
    let action: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(game.awayTeam) @ \(game.homeTeam)")
                    .font(.subheadline)
                    .foregroundStyle(isLocked ? AdaptiveColor.peOnSurfaceVar : AdaptiveColor.peOnSurface)
                HStack(spacing: 4) {
                    if isLocked {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(AdaptiveColor.peOnSurfaceVar)
                    }
                    Text(game.kickoffAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(AdaptiveColor.peOnSurfaceVar)
                }
            }
            Spacer()
            Button(action: action) {
                Image(systemName: isAdding ? "plus.circle.fill" : "minus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(isAdding ? AdaptiveColor.peSecondary : (isLocked ? AdaptiveColor.peOnSurfaceVar : AdaptiveColor.peError))
            }
            .buttonStyle(.borderless)
            .disabled(isLocked)
        }
    }
}

#Preview {
    SlateManageView(
        viewModel: SlateViewModel(
            group: MockData.group,
            gameRepository: MockGameRepository(),
            currentUserID: MockData.currentUserID
        )
    )
}
