import SwiftUI

struct CreateGroupView: View {
    var viewModel: GroupViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var mode: ChallengeMode = .season
    @State private var seasonYear: Int = Calendar.current.component(.year, from: Date())
    @State private var blindPicks = false
    @State private var superdogsEnabled = false
    @State private var superdogsPerUser = 3
    @State private var includePreseason = false
    @State private var includePlayoffs = true

    private var sportForMode: Sport {
        switch mode {
        case .season: return .nfl
        }
    }

    var body: some View {
        Form {
            Section {
                TextField(
                    "",
                    text: $name,
                    prompt: Text("Group name").foregroundStyle(AdaptiveColor.peOutline)
                )
                .textFieldStyle(.plain)
                .foregroundStyle(AdaptiveColor.peOnSurface)

                Picker("Challenge", selection: $mode) {
                    ForEach(ChallengeMode.allCases) { m in Text(m.displayName).tag(m) }
                }
                .foregroundStyle(AdaptiveColor.peOnSurface)

                Stepper("Year: \(seasonYear.formatted(.number.grouping(.never)))", value: $seasonYear, in: 2024...2034)
                    .foregroundStyle(AdaptiveColor.peOnSurface)
            } header: {
                Text("GROUP DETAILS")
                    .font(.peLabelBold())
                    .foregroundStyle(AdaptiveColor.peOnSurfaceVar)
            }
            .listRowBackground(AdaptiveColor.peSurfaceLow)

            Section {
                Toggle("Blind Picks", isOn: $blindPicks)
                    .foregroundStyle(AdaptiveColor.peOnSurface)
                    .tint(Color.peLimeFill)
            } header: {
                Text("PICK SETTINGS")
                    .font(.peLabelBold())
                    .foregroundStyle(AdaptiveColor.peOnSurfaceVar)
            }
            .listRowBackground(AdaptiveColor.peSurfaceLow)

            Section {
                Toggle("Enable Superdogs", isOn: $superdogsEnabled)
                    .foregroundStyle(AdaptiveColor.peOnSurface)
                    .tint(Color.peLimeFill)
                if superdogsEnabled {
                    Stepper("Superdogs per user: \(superdogsPerUser)", value: $superdogsPerUser, in: 1...10)
                        .foregroundStyle(AdaptiveColor.peOnSurface)
                }
            } header: {
                Text("SUPERDOGS")
                    .font(.peLabelBold())
                    .foregroundStyle(AdaptiveColor.peOnSurfaceVar)
            }
            .listRowBackground(AdaptiveColor.peSurfaceLow)

            Section {
                Toggle("Include Preseason", isOn: $includePreseason)
                    .foregroundStyle(AdaptiveColor.peOnSurface)
                    .tint(Color.peLimeFill)
                Toggle("Include Playoffs", isOn: $includePlayoffs)
                    .foregroundStyle(AdaptiveColor.peOnSurface)
                    .tint(Color.peLimeFill)
            } header: {
                Text("SCHEDULE")
                    .font(.peLabelBold())
                    .foregroundStyle(AdaptiveColor.peOnSurfaceVar)
            } footer: {
                Text("Controls which weeks are auto-populated from the schedule. You can still manually add a preseason or playoff week later either way.")
            }
            .listRowBackground(AdaptiveColor.peSurfaceLow)

            if let error = viewModel.errorMessage {
                Section {
                    Text(error)
                        .font(.peLabelSm())
                        .foregroundStyle(AdaptiveColor.peError)
                }
                .listRowBackground(AdaptiveColor.peSurfaceLow)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AdaptiveColor.peBackground)
        .navigationTitle("Create Group")
        .navigationBarTitleDisplayMode(.inline)
        .peNavBar()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .foregroundStyle(AdaptiveColor.pePrimary)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create") {
                    Task {
                        let group = await viewModel.createGroup(
                            name: name,
                            sport: sportForMode,
                            mode: mode,
                            seasonYear: seasonYear,
                            blindPicks: blindPicks,
                            superdogsEnabled: superdogsEnabled,
                            superdogsPerUser: superdogsPerUser,
                            includePreseason: includePreseason,
                            includePlayoffs: includePlayoffs
                        )
                        if group != nil { dismiss() }
                    }
                }
                .font(.peLabelBold())
                .foregroundStyle(name.isEmpty || viewModel.isLoading ? AdaptiveColor.peOutline : AdaptiveColor.pePrimaryFill)
                .disabled(name.isEmpty || viewModel.isLoading)
            }
        }
    }
}

#Preview {
    NavigationStack {
        CreateGroupView(viewModel: GroupViewModel(groupRepository: MockGroupRepository()))
    }
}
