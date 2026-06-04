import Foundation

enum Sport: String, Codable, CaseIterable, Identifiable {
    case nfl = "americanfootball_nfl"
    case worldCup = "soccer_fifa_world_cup"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .nfl: return "NFL"
        case .worldCup: return "World Cup"
        }
    }
}
