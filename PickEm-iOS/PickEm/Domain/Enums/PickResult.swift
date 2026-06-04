import Foundation

enum PickResult: String, Codable {
    case win
    case loss
    case superdogWin = "superdog_win"
    case pending

    var displayName: String {
        switch self {
        case .win: return "Win"
        case .loss: return "Loss"
        case .superdogWin: return "Superdog Win"
        case .pending: return "Pending"
        }
    }

    /// Point value this result contributes to the standings record.
    var winCount: Int {
        switch self {
        case .win: return 1
        case .superdogWin: return 3
        case .loss, .pending: return 0
        }
    }
}
