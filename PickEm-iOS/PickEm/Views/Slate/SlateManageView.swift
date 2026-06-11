import SwiftUI

struct SlateManageView: View {
    @Environment(\.dismiss) private var dismiss
    var viewModel: SlateViewModel
    @State private var managedWeekID: String?
    @State private var showNewWeekAlert = false
    @State private var newWeekLabel = ""
    @State private var alertError: String?

    private var managedWeek: Week? {
        viewModel.weeks.first { $0.id == managedWeekID }
            ?? viewModel.selectedWeek
    }

    var body: some View {
        NavigationStack {
            List {
                populateSection

                if viewModel.weeks.isEmpty {
                    noWeeksSection
                } else {
                    if viewModel.weeks.count > 1 {
                        weekPickerSection
                    }
                    if let week = managedWeek {
                        currentSlateSection(week: week)
                        availableGamesSection(week: week)
                    }
                }
            }
            .navigationTitle("Manage Slate")
            .navigationBarTitleDisplayMode(.inline)
            .peNavBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if !viewModel.weeks.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            newWeekLabel = ""
                            showNewWeekAlert = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .alert("New Week", isPresented: $showNewWeekAlert) {
                TextField("Label (e.g. Week 1)", text: $newWeekLabel)
                Button("Create") {
                    let label = newWeekLabel.trimmingCharacters(in: .whitespaces)
                    guard !label.isEmpty else { return }
                    Task {
                        do {
                            let week = try await viewModel.createWeek(label: label)
                            managedWeekID = week.id
                            await viewModel.fetchAvailableOdds()
                        } catch {
                            alertError = error.localizedDescription
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
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
            managedWeekID = viewModel.selectedWeek?.id
            await viewModel.fetchAvailableOdds()
        }
        .onChange(of: viewModel.selectedWeek) { _, newWeek in
            managedWeekID = newWeek?.id
        }
    }

    // MARK: - Sections

    private var populateSection: some View {
        Section {
            Button {
                Task {
                    await viewModel.populate()
                    managedWeekID = viewModel.selectedWeek?.id
                    await viewModel.fetchAvailableOdds()
                }
            } label: {
                HStack(spacing: 10) {
                    if viewModel.isPopulating {
                        ProgressView()
                    } else {
                        Image(systemName: "sparkles")
                            .foregroundStyle(AdaptiveColor.pePrimary)
                    }
                    Text("Populate from Pool")
                        .foregroundStyle(AdaptiveColor.pePrimary)
                }
            }
            .disabled(viewModel.isPopulating)
        } footer: {
            Text("Auto-creates weeks from available pool games, grouped by NFL week.")
        }
    }

    private var noWeeksSection: some View {
        Section {
            Button {
                newWeekLabel = ""
                showNewWeekAlert = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus.circle")
                        .foregroundStyle(AdaptiveColor.pePrimary)
                    Text("Create First Week")
                        .foregroundStyle(AdaptiveColor.pePrimary)
                }
            }
        }
    }

    private var weekPickerSection: some View {
        Section {
            Picker("Week", selection: $managedWeekID) {
                ForEach(viewModel.weeks) { week in
                    Text(week.label).tag(Optional(week.id))
                }
            }
        }
        .onChange(of: managedWeekID) { _, newID in
            guard let newID,
                  let week = viewModel.weeks.first(where: { $0.id == newID }) else { return }
            Task { await viewModel.selectWeek(week) }
        }
    }

    private func currentSlateSection(week: Week) -> some View {
        let slateLocked = viewModel.games.contains { $0.isLocked }
        return Section("In This Slate (\(viewModel.games.count))") {
            if viewModel.isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Loading…")
                        .foregroundStyle(.secondary)
                }
            } else if viewModel.games.isEmpty {
                Text("No games yet — add some below")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                if slateLocked {
                    Label("Slate is locked — games have kicked off", systemImage: "lock.fill")
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

    private func availableGamesSection(week: Week) -> some View {
        Section("Available to Add (\(viewModel.availableGames.count))") {
            if viewModel.availableGames.isEmpty {
                Text("No additional games in the pool")
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

// MARK: - Game row for manage view

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
