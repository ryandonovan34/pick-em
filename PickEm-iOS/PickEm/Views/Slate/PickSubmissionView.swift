import SwiftUI

struct PickSubmissionView: View {
    let game: Game
    let group: Group
    let existingPick: Pick?
    @Bindable var pickViewModel: PickViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTeam: String
    @State private var isSuperdog = false

    init(game: Game, group: Group, existingPick: Pick?, pickViewModel: PickViewModel) {
        self.game = game
        self.group = group
        self.existingPick = existingPick
        self.pickViewModel = pickViewModel
        _selectedTeam = State(initialValue: existingPick?.pickedTeam ?? game.awayTeam)
        _isSuperdog = State(initialValue: existingPick?.isSuperdog ?? false)
    }

    private var isUnderdogSelected: Bool { selectedTeam == game.underdogTeam }
    private var canSuperdog: Bool { group.superdogsEnabled && game.isSuperdogEligible && isUnderdogSelected }

    var body: some View {
        NavigationStack {
            Form {
                Section("Pick a team") {
                    TeamPickButton(
                        team: game.awayTeam,
                        spread: game.favoriteTeam == game.awayTeam ? game.spread : -game.spread,
                        isFavorite: game.favoriteTeam == game.awayTeam,
                        isSelected: selectedTeam == game.awayTeam,
                        action: { selectedTeam = game.awayTeam; isSuperdog = false }
                    )
                    TeamPickButton(
                        team: game.homeTeam,
                        spread: game.favoriteTeam == game.homeTeam ? game.spread : -game.spread,
                        isFavorite: game.favoriteTeam == game.homeTeam,
                        isSelected: selectedTeam == game.homeTeam,
                        action: { selectedTeam = game.homeTeam; isSuperdog = false }
                    )
                }
                .listRowBackground(AdaptiveColor.peSurfaceLow)

                if canSuperdog {
                    Section {
                        Toggle(isOn: $isSuperdog) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Declare Superdog")
                                    .font(.peHeadlineMd())
                                    .foregroundStyle(AdaptiveColor.peOnSurface)
                                Text("Pick the underdog to WIN outright for 3× points.")
                                    .font(.peBodyMd())
                                    .foregroundStyle(AdaptiveColor.peOnSurfaceVar)
                            }
                        }
                        .tint(Color.peLimeFill)
                    }
                    .listRowBackground(AdaptiveColor.peSurfaceLow)
                }

                if let error = pickViewModel.errorMessage {
                    Section {
                        Text(error)
                            .font(.peLabelSm())
                            .foregroundStyle(AdaptiveColor.peError)
                    }
                    .listRowBackground(AdaptiveColor.peSurfaceLow)
                }

                Section {
                    Button {
                        Task {
                            await pickViewModel.submitOrUpdate(game: game, pickedTeam: selectedTeam, isSuperdog: isSuperdog)
                            if pickViewModel.errorMessage == nil { dismiss() }
                        }
                    } label: {
                        if pickViewModel.isLoading {
                            ProgressView()
                                .tint(AdaptiveColor.peOnPrimary)
                                .frame(maxWidth: .infinity)
                        } else {
                            Text(existingPick == nil ? "Submit Pick" : "Update Pick")
                                .font(.peLabelBold())
                                .tracking(1.5)
                                .textCase(.uppercase)
                                .foregroundStyle(AdaptiveColor.peOnPrimary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(pickViewModel.isLoading)
                    .listRowBackground(AdaptiveColor.pePrimaryFill)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AdaptiveColor.peBackground)
            .navigationTitle("Make Your Pick")
            .navigationBarTitleDisplayMode(.inline)
            .peNavBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(AdaptiveColor.pePrimary)
                }
            }
        }
    }
}

// MARK: - Team Pick Button
private struct TeamPickButton: View {
    let team: String
    let spread: Double
    let isFavorite: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        let info = TeamInfo.from(team)
        return Button(action: action) {
            HStack(spacing: 14) {
                TeamIcon(fullName: team, size: 48)

                VStack(alignment: .leading, spacing: 2) {
                    Text(info.city)
                        .font(.peHeadlineMd())
                        .foregroundStyle(AdaptiveColor.peOnSurface)
                    Text(info.mascot)
                        .font(.peLabelSm())
                        .foregroundStyle(AdaptiveColor.peOnSurfaceVar)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(spread < 0 ? String(spread) : "+\(spread)")
                        .font(.peLabelBold())
                        .foregroundStyle(isFavorite ? AdaptiveColor.peOnSurface : AdaptiveColor.peSecondary)
                    Text(isFavorite ? "Favorite" : "Underdog")
                        .font(.peLabelSm())
                        .foregroundStyle(AdaptiveColor.peOnSurfaceVar)
                }

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AdaptiveColor.pePrimaryFill)
                        .font(.title3)
                }
            }
            .padding(.vertical, 4)
        }
        .tint(AdaptiveColor.peOnSurface)
        .listRowBackground(
            isSelected
                ? AdaptiveColor.pePrimaryFill.opacity(0.12)
                : AdaptiveColor.peSurfaceLow
        )
    }
}

#Preview {
    PickSubmissionView(
        game: MockData.games[0],
        group: MockData.group,
        existingPick: nil,
        pickViewModel: PickViewModel(
            group: MockData.group,
            currentUserID: MockData.currentUserID,
            pickRepository: MockPickRepository()
        )
    )
}
