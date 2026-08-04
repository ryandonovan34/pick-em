import Foundation

struct Week: Identifiable, Equatable, Hashable {
    let id: String
    let groupID: String
    let weekNumber: Int
    let label: String
    let createdAt: Date
    var firstKickoffAt: Date?
    var lastKickoffAt: Date?
    var startsOn: Date?   // Monday 00:00 UTC of the calendar week
    var endsOn: Date?     // Sunday 00:00 UTC of the calendar week

    /// True when the slate is currently underway (first game started, last game not yet finished).
    var isActive: Bool {
        let now = Date()
        guard let first = firstKickoffAt, let last = lastKickoffAt else { return false }
        return first <= now && last > now
    }

    /// True when all games in the slate are in the future.
    var isUpcoming: Bool {
        guard let first = firstKickoffAt else { return false }
        return first > Date()
    }

    /// Date-range label derived from startsOn/endsOn (e.g. "Jun 8 – Jun 14").
    /// Falls back to the stored label if date info is unavailable.
    var displayLabel: String {
        guard let start = startsOn, let end = endsOn else { return label }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return "\(fmt.string(from: start)) – \(fmt.string(from: end))"
    }
}
