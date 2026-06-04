import SwiftUI

struct GameRowView: View {
    let game: Game
    let pick: Pick?
    let group: Group
    let onPickTapped: () -> Void

    private var chipStyle: StatusChip.Style {
        if game.resultPosted { return .final_ }
        if game.hasKickedOff { return .live }
        return .upcoming
    }

    private var chipLabel: String {
        if game.resultPosted { return "FINAL" }
        if game.hasKickedOff { return "LIVE" }
        return game.kickoffAt.formatted(date: .omitted, time: .shortened)
    }

    private var accentBarColor: Color? {
        guard let pick else { return nil }
        switch pick.result {
        case .win, .superdogWin: return .peLimeFill
        case .loss:              return Color(hex: "ffb4ab")
        case .pending:           return Color(hex: "00d1ff")
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left accent bar — color indicates pick result
            if let barColor = accentBarColor {
                Rectangle()
                    .fill(barColor)
                    .frame(width: 3)
            }

            VStack(alignment: .leading, spacing: 12) {
                headerRow
                matchupRow
                if game.resultPosted, let home = game.homeScore, let away = game.awayScore {
                    scoreRow(away: away, home: home)
                }
                spreadLine
                pickRow
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

    // MARK: - Sub-views

    private var headerRow: some View {
        HStack {
            Text(game.kickoffAt.formatted(date: .abbreviated, time: .omitted))
                .font(.peLabelSm())
                .foregroundStyle(AdaptiveColor.peOnSurfaceVar)
            Spacer()
            StatusChip(label: chipLabel, style: chipStyle)
        }
    }

    private var matchupRow: some View {
        HStack(alignment: .top, spacing: 8) {
            teamColumn(team: game.awayTeam, isHome: false)
            teamColumn(team: game.homeTeam, isHome: true)
        }
    }

    private func scoreRow(away: Int, home: Int) -> some View {
        HStack {
            // Acronym + score for away
            Text("\(TeamInfo.from(game.awayTeam).acronym)  \(away)")
                .font(.peScore())
                .foregroundStyle(AdaptiveColor.peOnSurface)
            Spacer()
            // Score + acronym for home
            Text("\(home)  \(TeamInfo.from(game.homeTeam).acronym)")
                .font(.peScore())
                .foregroundStyle(AdaptiveColor.peOnSurface)
        }
    }

    private func teamColumn(team: String, isHome: Bool) -> some View {
        let info = TeamInfo.from(team)
        return HStack(alignment: .center, spacing: 8) {
            if !isHome {
                TeamIcon(fullName: team, size: 40)
            }
            VStack(alignment: isHome ? .trailing : .leading, spacing: 1) {
                Text(info.city)
                    .font(.peHeadlineMd())
                    .foregroundStyle(AdaptiveColor.peOnSurface)
                Text(info.mascot)
                    .font(.peLabelSm())
                    .foregroundStyle(AdaptiveColor.peOnSurfaceVar)
            }
            if isHome {
                TeamIcon(fullName: team, size: 40)
            }
        }
        .frame(maxWidth: .infinity, alignment: isHome ? .trailing : .leading)
    }

    private var spreadLine: some View {
        let favInfo = TeamInfo.from(game.favoriteTeam)
        let value = game.spread < 0 ? String(game.spread) : "+\(game.spread)"
        return HStack(spacing: 6) {
            Text("SPREAD")
                .font(.peLabelSm())
                .tracking(1)
                .foregroundStyle(AdaptiveColor.peOnSurfaceVar)
            Text("\(favInfo.acronym) \(value)")
                .font(.peLabelBold())
                .foregroundStyle(AdaptiveColor.peOnSurface)
        }
    }

    private var pickRow: some View {
        HStack {
            if let pick {
                PickBadge(pick: pick)
            } else if !game.isLocked {
                Text("No pick yet")
                    .font(.peLabelSm())
                    .foregroundStyle(AdaptiveColor.peOnSurfaceVar)
            }
            Spacer()
            if !game.isLocked {
                Button(pick == nil ? "Pick" : "Change") {
                    onPickTapped()
                }
                .font(.peLabelBold())
                .foregroundStyle(AdaptiveColor.pePrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(AdaptiveColor.pePrimary, lineWidth: 1.5)
                )
            }
        }
    }
}

// MARK: - Pick Badge
private struct PickBadge: View {
    let pick: Pick

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: iconName)
                .font(.caption.bold())
            // Full team name for pick display per design spec
            Text(pick.pickedTeam + (pick.isSuperdog ? " ★" : ""))
                .font(.peLabelBold())
        }
        .foregroundStyle(badgeColor)
    }

    private var iconName: String {
        switch pick.result {
        case .win, .superdogWin: return "trophy.fill"
        case .loss:              return "xmark.circle.fill"
        case .pending:           return "checkmark.circle.fill"
        }
    }

    private var badgeColor: AnyShapeStyle {
        switch pick.result {
        case .win, .superdogWin: AnyShapeStyle(AdaptiveColor.peSecondary)
        case .loss:              AnyShapeStyle(AdaptiveColor.peError)
        case .pending:           AnyShapeStyle(AdaptiveColor.pePrimary)
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        GameRowView(
            game: MockData.games[0],
            pick: MockData.picks.first(where: { $0.gameID == "game-1" }),
            group: MockData.group,
            onPickTapped: {}
        )
        GameRowView(
            game: MockData.games[3],
            pick: MockData.picks.first(where: { $0.gameID == "game-4" }),
            group: MockData.group,
            onPickTapped: {}
        )
    }
    .padding()
    .background(AdaptiveColor.peBackground)
}
