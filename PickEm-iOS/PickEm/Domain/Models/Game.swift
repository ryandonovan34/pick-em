import Foundation

struct Game: Identifiable, Equatable, Codable {
    let id: String
    let weekID: String
    let oddsAPIID: String?
    let sport: Sport
    let homeTeam: String
    let awayTeam: String
    /// Spread already rounded to nearest 0.5 (no push possible). Negative = home favorite.
    let spread: Double
    let favoriteTeam: String
    let kickoffAt: Date
    let homeScore: Int?
    let awayScore: Int?
    let resultPosted: Bool

    var hasKickedOff: Bool { kickoffAt <= Date() }

    var isLocked: Bool { hasKickedOff }

    /// The underdog team based on the favorite designation.
    var underdogTeam: String {
        favoriteTeam == homeTeam ? awayTeam : homeTeam
    }

    /// Whether this game qualifies for a superdog pick (spread magnitude >= 6.5 after rounding).
    var isSuperdogEligible: Bool {
        abs(spread) >= 6.5
    }

    /// Spread value rounded away from zero so half-point spreads are guaranteed (no push possible).
    /// Already applied at ingest time; exposed here for unit testing and display formatting.
    static func roundedSpread(_ rawSpread: Double) -> Double {
        // If the spread already ends in .5, no adjustment needed.
        let truncated = rawSpread.truncatingRemainder(dividingBy: 1)
        if abs(truncated) == 0.5 { return rawSpread }
        // Add 0.5 in the direction away from zero.
        return rawSpread < 0 ? rawSpread - 0.5 : rawSpread + 0.5
    }

    var spreadDisplay: String {
        let team = favoriteTeam
        let value = spread < 0 ? "\(spread)" : "+\(spread)"
        return "\(team) \(value)"
    }
}
