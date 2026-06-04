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
        nfl[fullName] ?? worldCup[fullName] ?? fallback(for: fullName)
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

// MARK: - World Cup Lookup
private extension TeamInfo {
    // swiftlint:disable opening_brace
    static let worldCup: [String: TeamInfo] = [
        "Argentina":      TeamInfo(city: "",            mascot: "Argentina",   acronym: "ARG", colorHex: "74ACDF"),
        "Australia":      TeamInfo(city: "",            mascot: "Australia",   acronym: "AUS", colorHex: "00843D"),
        "Belgium":        TeamInfo(city: "",            mascot: "Belgium",     acronym: "BEL", colorHex: "ED2939"),
        "Brazil":         TeamInfo(city: "",            mascot: "Brazil",      acronym: "BRA", colorHex: "009C3B"),
        "Canada":         TeamInfo(city: "",            mascot: "Canada",      acronym: "CAN", colorHex: "FF0000"),
        "Croatia":        TeamInfo(city: "",            mascot: "Croatia",     acronym: "CRO", colorHex: "FF0000"),
        "Denmark":        TeamInfo(city: "",            mascot: "Denmark",     acronym: "DEN", colorHex: "C60C30"),
        "Ecuador":        TeamInfo(city: "",            mascot: "Ecuador",     acronym: "ECU", colorHex: "FFD100"),
        "England":        TeamInfo(city: "",            mascot: "England",     acronym: "ENG", colorHex: "003099"),
        "France":         TeamInfo(city: "",            mascot: "France",      acronym: "FRA", colorHex: "002395"),
        "Germany":        TeamInfo(city: "",            mascot: "Germany",     acronym: "GER", colorHex: "000000"),
        "Ghana":          TeamInfo(city: "",            mascot: "Ghana",       acronym: "GHA", colorHex: "006B3F"),
        "Iran":           TeamInfo(city: "",            mascot: "Iran",        acronym: "IRN", colorHex: "239F40"),
        "Japan":          TeamInfo(city: "",            mascot: "Japan",       acronym: "JPN", colorHex: "BC002D"),
        "Mexico":         TeamInfo(city: "",            mascot: "Mexico",      acronym: "MEX", colorHex: "006847"),
        "Morocco":        TeamInfo(city: "",            mascot: "Morocco",     acronym: "MAR", colorHex: "C1272D"),
        "Netherlands":    TeamInfo(city: "",            mascot: "Netherlands", acronym: "NED", colorHex: "FF4F00"),
        "Poland":         TeamInfo(city: "",            mascot: "Poland",      acronym: "POL", colorHex: "DC143C"),
        "Portugal":       TeamInfo(city: "",            mascot: "Portugal",    acronym: "POR", colorHex: "006600"),
        "Saudi Arabia":   TeamInfo(city: "",            mascot: "Saudi Arabia",acronym: "KSA", colorHex: "006C35"),
        "Senegal":        TeamInfo(city: "",            mascot: "Senegal",     acronym: "SEN", colorHex: "00853F"),
        "Serbia":         TeamInfo(city: "",            mascot: "Serbia",      acronym: "SRB", colorHex: "C6363C"),
        "South Korea":    TeamInfo(city: "",            mascot: "South Korea", acronym: "KOR", colorHex: "CD2E3A"),
        "Spain":          TeamInfo(city: "",            mascot: "Spain",       acronym: "ESP", colorHex: "AA151B"),
        "Switzerland":    TeamInfo(city: "",            mascot: "Switzerland", acronym: "SUI", colorHex: "FF0000"),
        "Tunisia":        TeamInfo(city: "",            mascot: "Tunisia",     acronym: "TUN", colorHex: "E70013"),
        "United States":  TeamInfo(city: "",            mascot: "United States",acronym: "USA",colorHex: "0A3161"),
        "Uruguay":        TeamInfo(city: "",            mascot: "Uruguay",     acronym: "URU", colorHex: "5AAAFF"),
        "Wales":          TeamInfo(city: "",            mascot: "Wales",       acronym: "WAL", colorHex: "C8102E"),
    ]
    // swiftlint:enable opening_brace
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
