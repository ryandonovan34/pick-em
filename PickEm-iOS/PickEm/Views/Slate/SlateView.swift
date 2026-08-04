import SwiftUI

struct SlateView: View {
    var slateViewModel: SlateViewModel
    var pickViewModel: PickViewModel
    @State private var showNewWeekSheet = false

    var body: some View {
        List {
            ForEach(slateViewModel.weekGames) { wg in
                NavigationLink(value: wg.week) {
                    WeekRow(wg: wg, pickCount: pickCount(for: wg))
                }
                .listRowBackground(AdaptiveColor.peSurfaceLow)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AdaptiveColor.peBackground)
        .overlay {
            if slateViewModel.isLoading && slateViewModel.weekGames.isEmpty {
                LoadingView(message: "Loading weeks...")
            } else if let error = slateViewModel.errorMessage {
                ErrorView(message: error) {
                    Task { await slateViewModel.loadWeeks() }
                }
            } else if slateViewModel.weekGames.isEmpty {
                emptyOverlay
            }
        }
        .peNavBar()
        .toolbar { adminToolbar }
        .refreshable {
            await slateViewModel.refresh()
            await pickViewModel.loadAllPicks(groupID: slateViewModel.group.id)
        }
        .sheet(isPresented: $showNewWeekSheet) {
            NewWeekSheet(viewModel: slateViewModel)
        }
    }

    // MARK: - Pick count helper

    private func pickCount(for wg: WeekGames) -> Int {
        let gameIDs = Set(wg.games.map(\.id))
        return pickViewModel.picks.keys.filter { gameIDs.contains($0) }.count
    }

    // MARK: - Empty overlay

    @ViewBuilder
    private var emptyOverlay: some View {
        if slateViewModel.isAdmin {
            ContentUnavailableView {
                Label("No Weeks Yet", systemImage: "calendar.badge.plus")
            } description: {
                Text("Add the first week to start picking.")
            } actions: {
                Button("Add Week") { showNewWeekSheet = true }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            ContentUnavailableView(
                "No Weeks Yet",
                systemImage: "calendar.badge.exclamationmark",
                description: Text("Your commissioner hasn't set up any weeks yet.")
            )
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var adminToolbar: some ToolbarContent {
        if slateViewModel.isAdmin {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("New Week") { showNewWeekSheet = true }
                    Button("Sync Season Weeks") {
                        Task { await slateViewModel.syncStandardWeeks() }
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }
}

// MARK: - Week row

private struct WeekRow: View {
    let wg: WeekGames
    let pickCount: Int

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(wg.week.displayLabel)
                    .font(.peHeadlineMd())
                    .foregroundStyle(AdaptiveColor.peOnSurface)

                subtitle
                    .font(.peLabelSm())
                    .foregroundStyle(AdaptiveColor.peOnSurfaceVar)
            }

            Spacer()

            statusBadge
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var subtitle: some View {
        if wg.games.isEmpty {
            Text("No games yet")
        } else if wg.allLocked {
            Text("\(pickCount)/\(wg.games.count) picks • Results available")
        } else if wg.someLocked {
            let remaining = wg.games.filter { !$0.isLocked }.count
            Text("\(pickCount)/\(wg.games.count) picks • \(remaining) game\(remaining == 1 ? "" : "s") remaining")
        } else {
            Text("\(pickCount)/\(wg.games.count) picks made")
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if wg.games.isEmpty {
            EmptyView()
        } else if wg.allLocked {
            badge("PAST", foreground: AdaptiveColor.peOnSurfaceVar, background: AdaptiveColor.peOnSurfaceVar.opacity(0.12))
        } else if wg.someLocked {
            badge("LIVE", foreground: Color.green, background: Color.green.opacity(0.12))
        } else {
            badge("UPCOMING", foreground: AdaptiveColor.pePrimary, background: AdaptiveColor.pePrimary.opacity(0.12))
        }
    }

    private func badge<F: ShapeStyle, B: ShapeStyle>(_ text: String, foreground: F, background: B) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(background)
            .clipShape(Capsule())
    }
}

// MARK: - New week sheet

private struct NewWeekSheet: View {
    @Environment(\.dismiss) private var dismiss
    var viewModel: SlateViewModel

    @State private var startsOn: Date = {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? Date()
    }()
    @State private var isCreating = false
    @State private var errorMessage: String?

    private var endDate: Date {
        Calendar(identifier: .iso8601).date(byAdding: .day, value: 6, to: startsOn) ?? startsOn
    }

    private var autoLabel: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return "\(fmt.string(from: startsOn)) – \(fmt.string(from: endDate))"
    }

    @State private var useCustomEndDate = false
    @State private var customEndsOn: Date = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Week of", selection: $startsOn, displayedComponents: .date)
                        .onChange(of: startsOn) { _, newDate in
                            var cal = Calendar(identifier: .iso8601)
                            cal.timeZone = TimeZone(identifier: "UTC")!
                            if let monday = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: newDate)) {
                                startsOn = monday
                            }
                            customEndsOn = max(customEndsOn, startsOn)
                        }
                } header: {
                    Text("Calendar Week")
                } footer: {
                    Text("Games in this slate must kick off between \(autoLabel).")
                }

                Section {
                    Toggle("Custom end date", isOn: $useCustomEndDate)
                    if useCustomEndDate {
                        DatePicker("Ends on", selection: $customEndsOn, in: startsOn..., displayedComponents: .date)
                    }
                } footer: {
                    Text("Use this for slates that don't fit a standard 7-day week, like a playoff or holiday window.")
                }

                if let error = errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("New Week")
            .navigationBarTitleDisplayMode(.inline)
            .peNavBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isCreating {
                        ProgressView()
                    } else {
                        Button("Add") {
                            Task {
                                isCreating = true
                                do {
                                    _ = try await viewModel.createWeek(
                                        label: autoLabel,
                                        startsOn: startsOn,
                                        endsOn: useCustomEndDate ? customEndsOn : nil
                                    )
                                    dismiss()
                                } catch {
                                    errorMessage = error.localizedDescription
                                    isCreating = false
                                }
                            }
                        }
                    }
                }
            }
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
