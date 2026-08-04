import Foundation

struct Group: Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let adminID: String
    let joinCode: String
    let sport: Sport
    let mode: ChallengeMode
    let seasonYear: Int?
    let blindPicks: Bool
    let superdogsEnabled: Bool
    let superdogsPerUser: Int
    let includePreseason: Bool
    let includePlayoffs: Bool
    let createdAt: Date

    var isSeasonMode: Bool { mode == .season }
}
