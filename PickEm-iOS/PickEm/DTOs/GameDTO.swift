import Foundation

struct GameDTO: Codable {
    let id: String
    let weekID: String?
    let oddsAPIID: String?
    let sport: String
    let homeTeam: String
    let awayTeam: String
    let spread: Double
    let favoriteTeam: String
    let kickoffAt: Date
    let homeScore: Int?
    let awayScore: Int?
    let resultPosted: Bool

    enum CodingKeys: String, CodingKey {
        case id, sport, spread
        case weekID = "week_id"
        case oddsAPIID = "odds_api_id"
        case homeTeam = "home_team"
        case awayTeam = "away_team"
        case favoriteTeam = "favorite_team"
        case kickoffAt = "kickoff_at"
        case homeScore = "home_score"
        case awayScore = "away_score"
        case resultPosted = "result_posted"
    }

    func toDomain() -> Game {
        Game(
            id: id,
            weekID: weekID ?? "",
            oddsAPIID: oddsAPIID,
            sport: Sport(rawValue: sport) ?? .nfl,
            homeTeam: homeTeam,
            awayTeam: awayTeam,
            spread: spread,
            favoriteTeam: favoriteTeam,
            kickoffAt: kickoffAt,
            homeScore: homeScore,
            awayScore: awayScore,
            resultPosted: resultPosted
        )
    }
}

struct WeekDTO: Codable {
    let id: String
    let groupID: String
    let weekNumber: Int
    let label: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, label
        case groupID = "group_id"
        case weekNumber = "week_number"
        case createdAt = "created_at"
    }

    func toDomain() -> Week {
        Week(
            id: id,
            groupID: groupID,
            weekNumber: weekNumber,
            label: label,
            createdAt: createdAt
        )
    }
}
