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
    let createdAt: Date

    var isSeasonMode: Bool { mode == .season }
    var isWorldCupMode: Bool { mode == .worldCup }
    var isStructuredMode: Bool { mode == .season || mode == .worldCup }
}
