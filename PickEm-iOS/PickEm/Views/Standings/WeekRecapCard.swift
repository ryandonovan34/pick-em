import SwiftUI

/// Card shown at the top of the Standings tab once a week has at least one
/// posted result. Entirely optional/cosmetic — renders nothing at all on
/// devices/OS versions where Foundation Models isn't available, so members
/// on older hardware simply never see it.
struct WeekRecapCard: View {
    let week: Week
    let games: [Game]
    let standings: [Standing]
    var pickViewModel: PickViewModel

    @State private var state: RecapState = .idle

    private enum RecapState {
        case idle
        case loading
        case loaded(String)
        case failed
    }

    var body: some View {
        if RecapService.isAvailable {
            VStack(alignment: .leading, spacing: 10) {
                header
                content
            }
            .padding(14)
            .background(AdaptiveColor.peSurfaceLow)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AdaptiveColor.peOutlineVar, lineWidth: 1)
            )
        }
    }

    private var header: some View {
        HStack {
            Text("WEEKLY RECAP")
                .font(.peLabelSm())
                .tracking(1)
                .foregroundStyle(AdaptiveColor.peOnSurfaceVar)
            Spacer()
            if case .loaded = state {
                Button("Regenerate") { Task { await generate() } }
                    .font(.peLabelSm())
                    .foregroundStyle(AdaptiveColor.pePrimary)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle:
            Button("Generate Weekly Recap") { Task { await generate() } }
                .font(.peLabelBold())
                .foregroundStyle(AdaptiveColor.pePrimary)
        case .loading:
            HStack(spacing: 8) {
                ProgressView()
                Text("Writing this week's recap…")
                    .font(.peLabelSm())
                    .foregroundStyle(AdaptiveColor.peOnSurfaceVar)
            }
        case .loaded(let text):
            Text(text)
                .font(.peBodyMd())
                .foregroundStyle(AdaptiveColor.peOnSurface)
        case .failed:
            Text("Couldn't generate a recap right now.")
                .font(.peLabelSm())
                .foregroundStyle(AdaptiveColor.peOnSurfaceVar)
        }
    }

    private func generate() async {
        state = .loading
        // Loaded fresh on-demand rather than relying on whatever the shared
        // PickViewModel.allMemberPicks last held — that cache is scoped to
        // "whichever week was most recently viewed" (see WeekDetailView),
        // and by the time a user taps this button it may hold a different
        // week's picks.
        await pickViewModel.loadAllMemberPicks(weekID: week.id)
        do {
            let text = try await RecapService.generateRecap(
                games: games, memberPicks: pickViewModel.allMemberPicks, standings: standings
            )
            state = .loaded(text)
        } catch {
            state = .failed
        }
    }
}

#Preview {
    WeekRecapCard(
        week: MockData.week,
        games: MockData.games,
        standings: MockData.standings,
        pickViewModel: PickViewModel(
            group: MockData.group,
            currentUserID: MockData.currentUserID,
            pickRepository: MockPickRepository()
        )
    )
    .padding()
    .background(AdaptiveColor.peBackground)
}
