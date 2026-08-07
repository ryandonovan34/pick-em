import Foundation

/// One graded pick in a member's history — denormalized with enough game/week
/// context to render a full row without further lookups. Only ever contains
/// picks with a decided result (never .pending); see PickRepositoryProtocol.
struct PickHistoryEntry: Identifiable, Equatable, Hashable {
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
    let result: PickResult
    let homeScore: Int?
    let awayScore: Int?

    var id: String { pickID }

    var underdogTeam: String { favoriteTeam == homeTeam ? awayTeam : homeTeam }
    var pickedFavorite: Bool { pickedTeam == favoriteTeam }
}
