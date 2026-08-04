import Foundation

// Shared in-memory mock data used by all LocalMockRepository implementations.
//
// Mirrors the same season-progression narrative as pickem-api/scripts/seed_dev.py
// (Weeks 1-8 fully played out, Week 9 current with a final/live/upcoming mix) so
// MockLocal and MockBackend show equivalent-looking data.
enum MockData {
    static let currentUserID  = "user-1"
    static let otherUserID    = "user-2"
    static let thirdUserID    = "user-3"
    static let adminUserID    = "user-1"

    static let currentUser = User(
        id: currentUserID,
        email: "alice@example.com",
        displayName: "Alice",
        fcmToken: nil,
        createdAt: Date(timeIntervalSinceNow: -86400 * 30)
    )

    static let otherUser = User(
        id: otherUserID,
        email: "bob@example.com",
        displayName: "Bob",
        fcmToken: nil,
        createdAt: Date(timeIntervalSinceNow: -86400 * 20)
    )

    static let thirdUser = User(
        id: thirdUserID,
        email: "charlie@example.com",
        displayName: "Charlie",
        fcmToken: nil,
        createdAt: Date(timeIntervalSinceNow: -86400 * 25)
    )

    // MARK: - NFL Group

    static let nflGroup = Group(
        id: "group-1",
        name: "Sunday Crew",
        adminID: adminUserID,
        joinCode: "CREW23",
        sport: .nfl,
        mode: .season,
        seasonYear: 2025,
        blindPicks: false,
        superdogsEnabled: true,
        superdogsPerUser: 3,
        includePreseason: false,
        includePlayoffs: true,
        createdAt: Date(timeIntervalSinceNow: -86400 * 10)
    )

    // MARK: - Week 9 (current) — stable IDs (game-1..4) relied on by tests/previews

    private static func windowed(from games: [Game], id: String, groupID: String, weekNumber: Int, label: String, createdAt: Date) -> Week {
        let kickoffs = games.map(\.kickoffAt)
        let first = kickoffs.min()
        let last = kickoffs.max()
        var calendar = Calendar(identifier: .iso8601)
        // Must be Eastern, not UTC or the system's local timezone — NFL games
        // are scheduled in ET, and an 8+ PM ET kickoff (Sunday/Monday night
        // football) is already the next day in UTC, which would otherwise
        // push the ISO week boundary computed here out of sync with what
        // weeklySlotKickoff actually generated. (The stored startsOn/endsOn
        // are still fine to *display* via a UTC-timezone formatter afterward —
        // ET midnight always falls within the same UTC calendar day.)
        calendar.timeZone = eastern
        let starts = first.flatMap { calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: $0)) }
        // Only widen endsOn past the standard NFL week — Thursday through
        // the FOLLOWING Monday (MNF), i.e. +7 days from a Monday-anchored
        // starts_on, not +6 — when a game falls even after that (mirrors
        // auto_slate.py's _week_window / games.py's _week_end fallback).
        // Leaving it nil otherwise is what makes Week.displayLabel fall back
        // to the real "Week N" label instead of rendering a raw date range.
        // Compares CALENDAR DAYS (via startOfDay), not raw instants — an
        // evening kickoff's exact instant is always numerically later than
        // midnight of day 7 even when it's still calendar-day 7 in ET.
        var ends: Date?
        if let starts, let last,
           let sevenDaysLater = calendar.date(byAdding: .day, value: 7, to: starts),
           calendar.startOfDay(for: last) > sevenDaysLater {
            ends = last
        }
        return Week(
            id: id, groupID: groupID, weekNumber: weekNumber, label: label, createdAt: createdAt,
            firstKickoffAt: first, lastKickoffAt: last, startsOn: starts, endsOn: ends
        )
    }

    static let nflGames: [Game] = [
        Game(
            id: "game-1", weekID: "week-9", oddsAPIID: "odds-1", sport: .nfl,
            homeTeam: "Kansas City Chiefs", awayTeam: "Las Vegas Raiders",
            spread: -7.5, favoriteTeam: "Kansas City Chiefs",
            kickoffAt: Date(timeIntervalSinceNow: 3600 * 48),
            homeScore: nil, awayScore: nil, resultPosted: false
        ),
        Game(
            id: "game-2", weekID: "week-9", oddsAPIID: "odds-2", sport: .nfl,
            homeTeam: "San Francisco 49ers", awayTeam: "Dallas Cowboys",
            spread: -3.5, favoriteTeam: "San Francisco 49ers",
            kickoffAt: Date(timeIntervalSinceNow: 3600 * 50),
            homeScore: nil, awayScore: nil, resultPosted: false
        ),
        Game(
            id: "game-3", weekID: "week-9", oddsAPIID: "odds-3", sport: .nfl,
            homeTeam: "Philadelphia Eagles", awayTeam: "New York Giants",
            spread: -10.5, favoriteTeam: "Philadelphia Eagles",
            kickoffAt: Date(timeIntervalSinceNow: 3600 * 52),
            homeScore: nil, awayScore: nil, resultPosted: false
        ),
        Game(
            id: "game-4", weekID: "week-9", oddsAPIID: "odds-4", sport: .nfl,
            homeTeam: "Buffalo Bills", awayTeam: "Miami Dolphins",
            spread: -4.5, favoriteTeam: "Buffalo Bills",
            kickoffAt: Date(timeIntervalSinceNow: -3600),
            homeScore: 27, awayScore: 14, resultPosted: true
        )
    ]

    static let nflWeek: Week = windowed(
        from: nflGames, id: "week-9", groupID: "group-1", weekNumber: 9, label: "Week 9",
        createdAt: Date(timeIntervalSinceNow: -86400 * 7)
    )

    private static let week9Picks: [Pick] = [
        // Alice picked KC Chiefs for the upcoming game-1
        Pick(id: "pick-1", userID: currentUserID, gameID: "game-1", groupID: "group-1",
             pickedTeam: "Kansas City Chiefs", isSuperdog: false, result: .pending,
             createdAt: Date(timeIntervalSinceNow: -3600), updatedAt: Date(timeIntervalSinceNow: -3600)),

        // game-4 Bills -4.5 won 27-14 (covered)
        Pick(id: "pick-2", userID: currentUserID, gameID: "game-4", groupID: "group-1",
             pickedTeam: "Buffalo Bills", isSuperdog: false, result: .win,
             createdAt: Date(timeIntervalSinceNow: -86400), updatedAt: Date(timeIntervalSinceNow: -86400)),
        Pick(id: "pick-3", userID: otherUserID, gameID: "game-4", groupID: "group-1",
             pickedTeam: "Miami Dolphins", isSuperdog: false, result: .loss,
             createdAt: Date(timeIntervalSinceNow: -86400), updatedAt: Date(timeIntervalSinceNow: -86400)),
        Pick(id: "pick-3c", userID: thirdUserID, gameID: "game-4", groupID: "group-1",
             pickedTeam: "Buffalo Bills", isSuperdog: false, result: .win,
             createdAt: Date(timeIntervalSinceNow: -86400), updatedAt: Date(timeIntervalSinceNow: -86400))
    ]

    // MARK: - Week 10 (upcoming) — games exist, nobody has picked yet

    static let nflWeek13Games: [Game] = [
        Game(id: "game-w13-1", weekID: "week-10", oddsAPIID: "odds-w13-1", sport: .nfl,
             homeTeam: "Cincinnati Bengals", awayTeam: "Pittsburgh Steelers", spread: -3.5, favoriteTeam: "Cincinnati Bengals",
             kickoffAt: Date(timeIntervalSinceNow: 86400 * 4),
             homeScore: nil, awayScore: nil, resultPosted: false),
        Game(id: "game-w13-2", weekID: "week-10", oddsAPIID: "odds-w13-2", sport: .nfl,
             homeTeam: "Detroit Lions", awayTeam: "Chicago Bears", spread: -6.5, favoriteTeam: "Detroit Lions",
             kickoffAt: Date(timeIntervalSinceNow: 86400 * 5),
             homeScore: nil, awayScore: nil, resultPosted: false)
    ]

    static let nflWeek13: Week = windowed(
        from: nflWeek13Games, id: "week-10", groupID: "group-1", weekNumber: 10, label: "Week 10",
        createdAt: Date(timeIntervalSinceNow: -3600 * 2)
    )

    // MARK: - Weeks 1-8 (history) — deterministically generated so standings/dates
    // stay internally consistent without hand-authoring ~150 literals. One
    // eligible game gets a superdog pick so that state has a visible example too.

    private struct MatchupTemplate {
        let home: String, away: String, spread: Double
    }

    // Realistic NFL weekly time slots (mirrors pickem-api's
    // nfl_calendar.weekly_slot_kickoff): Thursday Night Football, Sunday's
    // early/late windows, and an alternating SNF/MNF closer.
    private static let eastern = TimeZone(identifier: "America/New_York")!

    private static func thursdayComponents(of date: Date) -> DateComponents {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let weekday = utc.component(.weekday, from: date) // 1=Sun...7=Sat
        let mondayBased = (weekday + 5) % 7 // Mon=0...Sun=6
        let daysSinceThursday = (mondayBased - 3 + 7) % 7
        let thursday = utc.date(byAdding: .day, value: -daysSinceThursday, to: date)!
        return utc.dateComponents([.year, .month, .day], from: thursday)
    }

    private static func etKickoff(_ thursday: DateComponents, dayOffset: Int, hour: Int, minute: Int) -> Date {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let baseDay = utc.date(from: thursday)!
        let targetDay = utc.date(byAdding: .day, value: dayOffset, to: baseDay)!
        let ymd = utc.dateComponents([.year, .month, .day], from: targetDay)

        var etCalendar = Calendar(identifier: .gregorian)
        etCalendar.timeZone = eastern
        var comps = DateComponents()
        comps.year = ymd.year; comps.month = ymd.month; comps.day = ymd.day
        comps.hour = hour; comps.minute = minute; comps.timeZone = eastern
        return etCalendar.date(from: comps)!
    }

    private static func weeklySlotKickoff(anchor: Date, slotIndex: Int, slotCount: Int, weekNumber: Int) -> Date {
        let thursday = thursdayComponents(of: anchor)
        if slotIndex == 0 {
            return etKickoff(thursday, dayOffset: 0, hour: 20, minute: 15) // Thursday Night Football
        }
        if slotCount >= 2 && slotIndex == slotCount - 1 {
            return weekNumber % 2 == 0
                ? etKickoff(thursday, dayOffset: 4, hour: 20, minute: 15)  // Monday Night Football
                : etKickoff(thursday, dayOffset: 3, hour: 20, minute: 20)  // Sunday Night Football
        }
        if slotCount >= 3 && slotIndex == slotCount - 2 {
            return etKickoff(thursday, dayOffset: 3, hour: 16, minute: 25) // Sunday late window
        }
        return etKickoff(thursday, dayOffset: 3, hour: 13, minute: 0)      // Sunday early window
    }

    private static let historyTemplates: [MatchupTemplate] = [
        .init(home: "Kansas City Chiefs", away: "Las Vegas Raiders", spread: -7.5),
        .init(home: "Buffalo Bills", away: "Miami Dolphins", spread: -6.5),
        .init(home: "San Francisco 49ers", away: "Dallas Cowboys", spread: -4.5),
        .init(home: "Philadelphia Eagles", away: "New York Giants", spread: -10.5),
        .init(home: "Baltimore Ravens", away: "Cleveland Browns", spread: -9.5),
        .init(home: "Green Bay Packers", away: "Minnesota Vikings", spread: -2.5),
        .init(home: "Seattle Seahawks", away: "Los Angeles Chargers", spread: -1.5),
        .init(home: "Tampa Bay Buccaneers", away: "New Orleans Saints", spread: -3.5),
    ]

    private static func buildHistory() -> (weeks: [Week], games: [Game], picks: [Pick]) {
        var weeks: [Week] = []
        var games: [Game] = []
        var picks: [Pick] = []
        var superdogAssigned = false

        for weekNumber in 1...8 {
            let weeksAgo = 9 - weekNumber
            let weekBase = Date(timeIntervalSinceNow: -Double(weeksAgo) * 7 * 86400)
            let offset = (weekNumber - 1) * 2
            var weekGames: [Game] = []

            for i in 0..<4 {
                let template = historyTemplates[(offset + i) % historyTemplates.count]
                let gameID = "w\(weekNumber)-g\(i + 1)"
                let kickoff = weeklySlotKickoff(anchor: weekBase, slotIndex: i, slotCount: 4, weekNumber: weekNumber)
                // Deterministic outcome: favorite covers ~2 of every 3 games.
                let favoriteCovers = (weekNumber + i) % 3 != 0
                let margin = Int(abs(template.spread))
                let (home, away): (Int, Int) = favoriteCovers
                    ? (17 + margin + 4, 17)
                    : (17 + max(1, margin - 3), 17 + margin + 2) // favorite wins outright but underdog covers, or underdog wins

                let game = Game(
                    id: gameID, weekID: "week-h\(weekNumber)", oddsAPIID: "odds-\(gameID)", sport: .nfl,
                    homeTeam: template.home, awayTeam: template.away,
                    spread: template.spread, favoriteTeam: template.home,
                    kickoffAt: kickoff, homeScore: home, awayScore: away, resultPosted: true
                )
                weekGames.append(game)
                games.append(game)

                let underdogWonOutright = away > home
                let eligibleForSuperdog = !superdogAssigned && abs(template.spread) >= 6.5

                for (userID, favors) in [(currentUserID, true), (otherUserID, (weekNumber + i) % 2 == 0), (thirdUserID, (weekNumber + i) % 3 != 1)] {
                    let isSuperdog = eligibleForSuperdog && userID == currentUserID
                    if isSuperdog { superdogAssigned = true }

                    let pickedTeam = isSuperdog ? template.away : (favors ? template.home : template.away)
                    let result: PickResult
                    if isSuperdog {
                        result = underdogWonOutright ? .superdogWin : .loss
                    } else if pickedTeam == template.home {
                        result = favoriteCovers ? .win : .loss
                    } else {
                        result = favoriteCovers ? .loss : .win
                    }

                    picks.append(Pick(
                        id: "pick-\(gameID)-\(userID)", userID: userID, gameID: gameID, groupID: "group-1",
                        pickedTeam: pickedTeam, isSuperdog: isSuperdog, result: result,
                        createdAt: kickoff.addingTimeInterval(-3600), updatedAt: kickoff.addingTimeInterval(-3600)
                    ))
                }
            }

            weeks.append(windowed(
                from: weekGames, id: "week-h\(weekNumber)", groupID: "group-1",
                weekNumber: weekNumber, label: "Week \(weekNumber)",
                createdAt: weekBase.addingTimeInterval(-86400)
            ))
        }

        return (weeks, games, picks)
    }

    private static let history = buildHistory()

    // MARK: - Combined

    static var group: Group { nflGroup }
    static var week: Week { nflWeek }
    static var allWeeks: [Week] { [nflWeek] + history.weeks + [nflWeek13] }
    static var games: [Game] { nflGames + history.games + nflWeek13Games }
    static var picks: [Pick] { week9Picks + history.picks }

    // MARK: - Standings — tallied from `picks` so they can never drift out of sync.

    static var standings: [Standing] {
        let users: [(id: String, name: String)] = [
            (currentUserID, "Alice"), (otherUserID, "Bob"), (thirdUserID, "Charlie"),
        ]
        return users.map { user in
            let userPicks = picks.filter { $0.userID == user.id && $0.groupID == "group-1" }
            let wins = userPicks.filter { $0.result == .win }.count
            let losses = userPicks.filter { $0.result == .loss }.count
            let superdogWins = userPicks.filter { $0.result == .superdogWin }.count
            return Standing(
                userID: user.id, groupID: "group-1", displayName: user.name,
                wins: wins, losses: losses, superdogWins: superdogWins, superdogsUsed: superdogWins,
                updatedAt: Date(timeIntervalSinceNow: -3600)
            )
        }
    }
}
