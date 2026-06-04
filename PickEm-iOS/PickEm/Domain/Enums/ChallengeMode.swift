import Foundation

enum ChallengeMode: String, Codable, CaseIterable, Identifiable {
    case season
    case worldCup

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .season: return "NFL Season"
        case .worldCup: return "World Cup"
        }
    }
}
