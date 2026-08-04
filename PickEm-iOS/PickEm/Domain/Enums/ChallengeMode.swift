import Foundation

enum ChallengeMode: String, Codable, CaseIterable, Identifiable {
    case season

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .season: return "NFL Season"
        }
    }
}
