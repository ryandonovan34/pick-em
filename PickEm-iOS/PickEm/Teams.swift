import SwiftUI

// MARK: - TeamInfo
struct TeamInfo {
    let city: String
    let mascot: String
    let acronym: String
    let colorHex: String

    var color: Color { Color(hex: colorHex) }

    /// Text color on the icon — dark for light team colors, white for dark ones.
    var iconTextColor: Color {
        var int: UInt64 = 0
        Scanner(string: colorHex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >>  8) & 0xFF) / 255.0
        let b = Double( int        & 0xFF) / 255.0
        let lum = 0.299 * r + 0.587 * g + 0.114 * b
        return lum > 0.45 ? Color(hex: "191c1d") : .white
    }

    static func from(_ fullName: String) -> TeamInfo {
        nfl[fullName] ?? fallback(for: fullName)
    }

    private static func fallback(for fullName: String) -> TeamInfo {
        let words = fullName.split(separator: " ").map(String.init)
        let mascot = words.last ?? fullName
        let city = words.dropLast().joined(separator: " ")
        let acronym = words.prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
        return TeamInfo(
            city: city.isEmpty ? fullName : city,
            mascot: mascot,
            acronym: acronym.isEmpty ? "?" : String(acronym.prefix(3)),
            colorHex: "4A5860"
        )
    }
}

// MARK: - TeamIcon
struct TeamIcon: View {
    let fullName: String
    var size: CGFloat = 44

    private var info: TeamInfo { TeamInfo.from(fullName) }

    var body: some View {
        Circle()
            .fill(info.color)
            .frame(width: size, height: size)
            .overlay(
                Text(info.acronym)
                    .font(.system(size: size * 0.31, weight: .heavy).width(.condensed))
                    .foregroundStyle(info.iconTextColor)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            )
    }
}

// MARK: - NFL Lookup
private extension TeamInfo {
    // swiftlint:disable opening_brace
    static let nfl: [String: TeamInfo] = [
        // AFC East
        "Buffalo Bills":           TeamInfo(city: "Buffalo",       mascot: "Bills",       acronym: "BUF", colorHex: "00338D"),
        "Miami Dolphins":          TeamInfo(city: "Miami",         mascot: "Dolphins",    acronym: "MIA", colorHex: "008E97"),
        "New England Patriots":    TeamInfo(city: "New England",   mascot: "Patriots",    acronym: "NE",  colorHex: "002244"),
        "New York Jets":           TeamInfo(city: "New York",      mascot: "Jets",        acronym: "NYJ", colorHex: "125740"),
        // AFC North
        "Baltimore Ravens":        TeamInfo(city: "Baltimore",     mascot: "Ravens",      acronym: "BAL", colorHex: "241773"),
        "Cincinnati Bengals":      TeamInfo(city: "Cincinnati",    mascot: "Bengals",     acronym: "CIN", colorHex: "FB4F14"),
        "Cleveland Browns":        TeamInfo(city: "Cleveland",     mascot: "Browns",      acronym: "CLE", colorHex: "FF3C00"),
        "Pittsburgh Steelers":     TeamInfo(city: "Pittsburgh",    mascot: "Steelers",    acronym: "PIT", colorHex: "FFB612"),
        // AFC South
        "Houston Texans":          TeamInfo(city: "Houston",       mascot: "Texans",      acronym: "HOU", colorHex: "03202F"),
        "Indianapolis Colts":      TeamInfo(city: "Indianapolis",  mascot: "Colts",       acronym: "IND", colorHex: "003D7F"),
        "Jacksonville Jaguars":    TeamInfo(city: "Jacksonville",  mascot: "Jaguars",     acronym: "JAX", colorHex: "006778"),
        "Tennessee Titans":        TeamInfo(city: "Tennessee",     mascot: "Titans",      acronym: "TEN", colorHex: "0C2340"),
        // AFC West
        "Denver Broncos":          TeamInfo(city: "Denver",        mascot: "Broncos",     acronym: "DEN", colorHex: "FB4F14"),
        "Kansas City Chiefs":      TeamInfo(city: "Kansas City",   mascot: "Chiefs",      acronym: "KC",  colorHex: "E31837"),
        "Las Vegas Raiders":       TeamInfo(city: "Las Vegas",     mascot: "Raiders",     acronym: "LV",  colorHex: "A5ACAF"),
        "Los Angeles Chargers":    TeamInfo(city: "Los Angeles",   mascot: "Chargers",    acronym: "LAC", colorHex: "0080C6"),
        // NFC East
        "Dallas Cowboys":          TeamInfo(city: "Dallas",        mascot: "Cowboys",     acronym: "DAL", colorHex: "003594"),
        "New York Giants":         TeamInfo(city: "New York",      mascot: "Giants",      acronym: "NYG", colorHex: "0B2265"),
        "Philadelphia Eagles":     TeamInfo(city: "Philadelphia",  mascot: "Eagles",      acronym: "PHI", colorHex: "004C54"),
        "Washington Commanders":   TeamInfo(city: "Washington",    mascot: "Commanders",  acronym: "WAS", colorHex: "5A1414"),
        // NFC North
        "Chicago Bears":           TeamInfo(city: "Chicago",       mascot: "Bears",       acronym: "CHI", colorHex: "0B162A"),
        "Detroit Lions":           TeamInfo(city: "Detroit",       mascot: "Lions",       acronym: "DET", colorHex: "0076B6"),
        "Green Bay Packers":       TeamInfo(city: "Green Bay",     mascot: "Packers",     acronym: "GB",  colorHex: "203731"),
        "Minnesota Vikings":       TeamInfo(city: "Minnesota",     mascot: "Vikings",     acronym: "MIN", colorHex: "4F2683"),
        // NFC South
        "Atlanta Falcons":         TeamInfo(city: "Atlanta",       mascot: "Falcons",     acronym: "ATL", colorHex: "A71930"),
        "Carolina Panthers":       TeamInfo(city: "Carolina",      mascot: "Panthers",    acronym: "CAR", colorHex: "0085CA"),
        "New Orleans Saints":      TeamInfo(city: "New Orleans",   mascot: "Saints",      acronym: "NO",  colorHex: "9F8958"),
        "Tampa Bay Buccaneers":    TeamInfo(city: "Tampa Bay",     mascot: "Buccaneers",  acronym: "TB",  colorHex: "D50A0A"),
        // NFC West
        "Arizona Cardinals":       TeamInfo(city: "Arizona",       mascot: "Cardinals",   acronym: "ARI", colorHex: "97233F"),
        "Los Angeles Rams":        TeamInfo(city: "Los Angeles",   mascot: "Rams",        acronym: "LAR", colorHex: "003594"),
        "San Francisco 49ers":     TeamInfo(city: "San Francisco", mascot: "49ers",       acronym: "SF",  colorHex: "AA0000"),
        "Seattle Seahawks":        TeamInfo(city: "Seattle",       mascot: "Seahawks",    acronym: "SEA", colorHex: "002244"),
    ]
    // swiftlint:enable opening_brace
}

#Preview {
    HStack(spacing: 12) {
        TeamIcon(fullName: "Kansas City Chiefs", size: 50)
        TeamIcon(fullName: "Miami Dolphins", size: 50)
        TeamIcon(fullName: "Pittsburgh Steelers", size: 50)
        TeamIcon(fullName: "Las Vegas Raiders", size: 50)
    }
    .padding()
}
