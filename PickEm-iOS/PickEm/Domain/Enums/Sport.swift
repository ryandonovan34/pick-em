import Foundation

enum Sport: String, Codable, CaseIterable, Identifiable {
    case nfl = "americanfootball_nfl"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .nfl: return "NFL"
        }
    }
}
