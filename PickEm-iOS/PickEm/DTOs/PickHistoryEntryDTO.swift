import Foundation

struct PickHistoryEntryDTO: Codable {
    let pickID: String
    let gameID: String
    let weekNumber: Int
    let weekLabel: String
    let homeTeam: String
    let awayTeam: String
    let pickedTeam: String
    let favoriteTeam: String
    let spread: Double
    let kickoffAt: Date
    let isSuperdog: Bool
    let isForfeit: Bool
    let result: String
    let homeScore: Int?
    let awayScore: Int?

    enum CodingKeys: String, CodingKey {
        case spread, result
        case pickID = "pick_id"
        case gameID = "game_id"
        case weekNumber = "week_number"
        case weekLabel = "week_label"
        case homeTeam = "home_team"
        case awayTeam = "away_team"
        case pickedTeam = "picked_team"
        case favoriteTeam = "favorite_team"
        case kickoffAt = "kickoff_at"
        case isSuperdog = "is_superdog"
        case isForfeit = "is_forfeit"
        case homeScore = "home_score"
        case awayScore = "away_score"
    }

    func toDomain() -> PickHistoryEntry {
        PickHistoryEntry(
            pickID: pickID,
            gameID: gameID,
            weekNumber: weekNumber,
            weekLabel: weekLabel,
            homeTeam: homeTeam,
            awayTeam: awayTeam,
            pickedTeam: pickedTeam,
            favoriteTeam: favoriteTeam,
            spread: spread,
            kickoffAt: kickoffAt,
            isSuperdog: isSuperdog,
            isForfeit: isForfeit,
            result: PickResult(rawValue: result) ?? .pending,
            homeScore: homeScore,
            awayScore: awayScore
        )
    }
}
