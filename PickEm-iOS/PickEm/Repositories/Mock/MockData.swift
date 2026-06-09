import Foundation

// Shared in-memory mock data used by all LocalMockRepository implementations.
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
        createdAt: Date(timeIntervalSinceNow: -86400 * 10)
    )

    // Past week — all games finalized
    static let nflWeek11 = Week(
        id: "week-11",
        groupID: "group-1",
        weekNumber: 11,
        label: "Week 11",
        createdAt: Date(timeIntervalSinceNow: -86400 * 14)
    )

    static let nflWeek11Games: [Game] = [
        // Chiefs -7.5 vs Raiders: Chiefs win 28-10 (covered by 18)
        Game(
            id: "game-w11-1",
            weekID: "week-11",
            oddsAPIID: "odds-w11-1",
            sport: .nfl,
            homeTeam: "Kansas City Chiefs",
            awayTeam: "Las Vegas Raiders",
            spread: -7.5,
            favoriteTeam: "Kansas City Chiefs",
            kickoffAt: Date(timeIntervalSinceNow: -86400 * 7 - 3600 * 4),
            homeScore: 28,
            awayScore: 10,
            resultPosted: true
        ),
        // 49ers -4.5 vs Cowboys: Cowboys win 24-17 (49ers didn't cover)
        Game(
            id: "game-w11-2",
            weekID: "week-11",
            oddsAPIID: "odds-w11-2",
            sport: .nfl,
            homeTeam: "San Francisco 49ers",
            awayTeam: "Dallas Cowboys",
            spread: -4.5,
            favoriteTeam: "San Francisco 49ers",
            kickoffAt: Date(timeIntervalSinceNow: -86400 * 7 - 3600 * 3),
            homeScore: 17,
            awayScore: 24,
            resultPosted: true
        ),
        // Eagles -10.5 vs Giants: Eagles win 35-7 (covered by 28)
        Game(
            id: "game-w11-3",
            weekID: "week-11",
            oddsAPIID: "odds-w11-3",
            sport: .nfl,
            homeTeam: "Philadelphia Eagles",
            awayTeam: "New York Giants",
            spread: -10.5,
            favoriteTeam: "Philadelphia Eagles",
            kickoffAt: Date(timeIntervalSinceNow: -86400 * 7 - 3600),
            homeScore: 35,
            awayScore: 7,
            resultPosted: true
        ),
        // Bills -6.5 vs Dolphins: Dolphins win outright 24-21 (superdog eligible, Dolphins won)
        Game(
            id: "game-w11-4",
            weekID: "week-11",
            oddsAPIID: "odds-w11-4",
            sport: .nfl,
            homeTeam: "Buffalo Bills",
            awayTeam: "Miami Dolphins",
            spread: -6.5,
            favoriteTeam: "Buffalo Bills",
            kickoffAt: Date(timeIntervalSinceNow: -86400 * 7),
            homeScore: 21,
            awayScore: 24,
            resultPosted: true
        )
    ]

    // Current week — mix of finalized and upcoming
    static let nflWeek = Week(
        id: "week-1",
        groupID: "group-1",
        weekNumber: 12,
        label: "Week 12",
        createdAt: Date(timeIntervalSinceNow: -86400 * 7)
    )

    static let nflGames: [Game] = [
        Game(
            id: "game-1",
            weekID: "week-1",
            oddsAPIID: "odds-1",
            sport: .nfl,
            homeTeam: "Kansas City Chiefs",
            awayTeam: "Las Vegas Raiders",
            spread: -7.5,
            favoriteTeam: "Kansas City Chiefs",
            kickoffAt: Date(timeIntervalSinceNow: 3600 * 48),
            homeScore: nil,
            awayScore: nil,
            resultPosted: false
        ),
        Game(
            id: "game-2",
            weekID: "week-1",
            oddsAPIID: "odds-2",
            sport: .nfl,
            homeTeam: "San Francisco 49ers",
            awayTeam: "Dallas Cowboys",
            spread: -3.5,
            favoriteTeam: "San Francisco 49ers",
            kickoffAt: Date(timeIntervalSinceNow: 3600 * 50),
            homeScore: nil,
            awayScore: nil,
            resultPosted: false
        ),
        Game(
            id: "game-3",
            weekID: "week-1",
            oddsAPIID: "odds-3",
            sport: .nfl,
            homeTeam: "Philadelphia Eagles",
            awayTeam: "New York Giants",
            spread: -10.5,
            favoriteTeam: "Philadelphia Eagles",
            kickoffAt: Date(timeIntervalSinceNow: 3600 * 52),
            homeScore: nil,
            awayScore: nil,
            resultPosted: false
        ),
        Game(
            id: "game-4",
            weekID: "week-1",
            oddsAPIID: "odds-4",
            sport: .nfl,
            homeTeam: "Buffalo Bills",
            awayTeam: "Miami Dolphins",
            spread: -4.5,
            favoriteTeam: "Buffalo Bills",
            kickoffAt: Date(timeIntervalSinceNow: -3600),
            homeScore: 27,
            awayScore: 14,
            resultPosted: true
        )
    ]

    // MARK: - World Cup Group

    static let worldCupGroup = Group(
        id: "group-2",
        name: "World Cup 2026",
        adminID: adminUserID,
        joinCode: "WC2026",
        sport: .worldCup,
        mode: .worldCup,
        seasonYear: 2026,
        blindPicks: true,
        superdogsEnabled: false,
        superdogsPerUser: 0,
        createdAt: Date(timeIntervalSinceNow: -86400 * 5)
    )

    static let worldCupWeek = Week(
        id: "week-2",
        groupID: "group-2",
        weekNumber: 1,
        label: "Group Stage - Matchday 1",
        createdAt: Date(timeIntervalSinceNow: -86400 * 5)
    )

    static let worldCupGames: [Game] = [
        // France -1.5 vs Morocco: France win 2-0 (covered)
        Game(
            id: "game-5",
            weekID: "week-2",
            oddsAPIID: "odds-5",
            sport: .worldCup,
            homeTeam: "France",
            awayTeam: "Morocco",
            spread: -1.5,
            favoriteTeam: "France",
            kickoffAt: Date(timeIntervalSinceNow: -86400 * 3),
            homeScore: 2,
            awayScore: 0,
            resultPosted: true
        ),
        // Brazil -1.5 vs Croatia: Brazil win 3-1 (covered)
        Game(
            id: "game-6",
            weekID: "week-2",
            oddsAPIID: "odds-6",
            sport: .worldCup,
            homeTeam: "Brazil",
            awayTeam: "Croatia",
            spread: -1.5,
            favoriteTeam: "Brazil",
            kickoffAt: Date(timeIntervalSinceNow: -86400),
            homeScore: 3,
            awayScore: 1,
            resultPosted: true
        ),
        Game(
            id: "game-7",
            weekID: "week-2",
            oddsAPIID: "odds-7",
            sport: .worldCup,
            homeTeam: "United States",
            awayTeam: "Mexico",
            spread: -0.5,
            favoriteTeam: "United States",
            kickoffAt: Date(timeIntervalSinceNow: 3600 * 48),
            homeScore: nil,
            awayScore: nil,
            resultPosted: false
        ),
        Game(
            id: "game-8",
            weekID: "week-2",
            oddsAPIID: "odds-8",
            sport: .worldCup,
            homeTeam: "Argentina",
            awayTeam: "Germany",
            spread: -1.5,
            favoriteTeam: "Argentina",
            kickoffAt: Date(timeIntervalSinceNow: 3600 * 96),
            homeScore: nil,
            awayScore: nil,
            resultPosted: false
        )
    ]

    // MARK: - Combined

    static var group: Group { nflGroup }
    static var week: Week { nflWeek }
    static var games: [Game] { nflWeek11Games + nflGames + worldCupGames }

    // MARK: - Picks
    //
    // NFL Week 11 results (Alice: 2W 1L 1SD, Bob: 2W 2L, Charlie: 1W 2L):
    //   w11-1  KC Chiefs covered   → Alice WIN, Bob WIN,  Charlie LOSS
    //   w11-2  Cowboys won outright → Alice LOSS, Bob WIN, Charlie WIN
    //   w11-3  Eagles covered      → Alice WIN, Bob LOSS, Charlie LOSS
    //   w11-4  Dolphins won outright (superdog eligible) → Alice SUPERDOG_WIN, Bob LOSS, Charlie LOSS
    //
    // NFL Week 12 partial (game-4 finalized, Bills -4.5 win 27-14, Bills covered):
    //   Alice WIN, Bob LOSS, Charlie WIN
    //
    // World Cup Matchday 1 (game-5 France covered, game-6 Brazil covered):
    //   game-5: Alice WIN, Bob LOSS, Charlie WIN
    //   game-6: Alice WIN, Bob WIN,  Charlie LOSS
    static let picks: [Pick] = [

        // ── NFL Week 11 ──────────────────────────────────────────────────────

        Pick(id: "pick-w11-1a", userID: currentUserID, gameID: "game-w11-1", groupID: "group-1",
             pickedTeam: "Kansas City Chiefs", isSuperdog: false, result: .win,
             createdAt: Date(timeIntervalSinceNow: -86400 * 8), updatedAt: Date(timeIntervalSinceNow: -86400 * 8)),
        Pick(id: "pick-w11-1b", userID: otherUserID, gameID: "game-w11-1", groupID: "group-1",
             pickedTeam: "Kansas City Chiefs", isSuperdog: false, result: .win,
             createdAt: Date(timeIntervalSinceNow: -86400 * 8), updatedAt: Date(timeIntervalSinceNow: -86400 * 8)),
        Pick(id: "pick-w11-1c", userID: thirdUserID, gameID: "game-w11-1", groupID: "group-1",
             pickedTeam: "Las Vegas Raiders", isSuperdog: false, result: .loss,
             createdAt: Date(timeIntervalSinceNow: -86400 * 8), updatedAt: Date(timeIntervalSinceNow: -86400 * 8)),

        Pick(id: "pick-w11-2a", userID: currentUserID, gameID: "game-w11-2", groupID: "group-1",
             pickedTeam: "San Francisco 49ers", isSuperdog: false, result: .loss,
             createdAt: Date(timeIntervalSinceNow: -86400 * 8), updatedAt: Date(timeIntervalSinceNow: -86400 * 8)),
        Pick(id: "pick-w11-2b", userID: otherUserID, gameID: "game-w11-2", groupID: "group-1",
             pickedTeam: "Dallas Cowboys", isSuperdog: false, result: .win,
             createdAt: Date(timeIntervalSinceNow: -86400 * 8), updatedAt: Date(timeIntervalSinceNow: -86400 * 8)),
        Pick(id: "pick-w11-2c", userID: thirdUserID, gameID: "game-w11-2", groupID: "group-1",
             pickedTeam: "Dallas Cowboys", isSuperdog: false, result: .win,
             createdAt: Date(timeIntervalSinceNow: -86400 * 8), updatedAt: Date(timeIntervalSinceNow: -86400 * 8)),

        Pick(id: "pick-w11-3a", userID: currentUserID, gameID: "game-w11-3", groupID: "group-1",
             pickedTeam: "Philadelphia Eagles", isSuperdog: false, result: .win,
             createdAt: Date(timeIntervalSinceNow: -86400 * 8), updatedAt: Date(timeIntervalSinceNow: -86400 * 8)),
        Pick(id: "pick-w11-3b", userID: otherUserID, gameID: "game-w11-3", groupID: "group-1",
             pickedTeam: "New York Giants", isSuperdog: false, result: .loss,
             createdAt: Date(timeIntervalSinceNow: -86400 * 8), updatedAt: Date(timeIntervalSinceNow: -86400 * 8)),
        Pick(id: "pick-w11-3c", userID: thirdUserID, gameID: "game-w11-3", groupID: "group-1",
             pickedTeam: "New York Giants", isSuperdog: false, result: .loss,
             createdAt: Date(timeIntervalSinceNow: -86400 * 8), updatedAt: Date(timeIntervalSinceNow: -86400 * 8)),

        // Alice superdogs the Dolphins (Bills -6.5, Dolphins won outright 24-21)
        Pick(id: "pick-w11-4a", userID: currentUserID, gameID: "game-w11-4", groupID: "group-1",
             pickedTeam: "Miami Dolphins", isSuperdog: true, result: .superdogWin,
             createdAt: Date(timeIntervalSinceNow: -86400 * 8), updatedAt: Date(timeIntervalSinceNow: -86400 * 8)),
        Pick(id: "pick-w11-4b", userID: otherUserID, gameID: "game-w11-4", groupID: "group-1",
             pickedTeam: "Buffalo Bills", isSuperdog: false, result: .loss,
             createdAt: Date(timeIntervalSinceNow: -86400 * 8), updatedAt: Date(timeIntervalSinceNow: -86400 * 8)),
        Pick(id: "pick-w11-4c", userID: thirdUserID, gameID: "game-w11-4", groupID: "group-1",
             pickedTeam: "Buffalo Bills", isSuperdog: false, result: .loss,
             createdAt: Date(timeIntervalSinceNow: -86400 * 8), updatedAt: Date(timeIntervalSinceNow: -86400 * 8)),

        // ── NFL Week 12 (game-4 only finalized so far) ────────────────────────

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
             createdAt: Date(timeIntervalSinceNow: -86400), updatedAt: Date(timeIntervalSinceNow: -86400)),

        // ── World Cup Matchday 1 ──────────────────────────────────────────────

        // game-5 France -1.5 won 2-0 (covered)
        Pick(id: "pick-4", userID: currentUserID, gameID: "game-5", groupID: "group-2",
             pickedTeam: "France", isSuperdog: false, result: .win,
             createdAt: Date(timeIntervalSinceNow: -86400 * 3), updatedAt: Date(timeIntervalSinceNow: -86400 * 3)),
        Pick(id: "pick-5", userID: otherUserID, gameID: "game-5", groupID: "group-2",
             pickedTeam: "Morocco", isSuperdog: false, result: .loss,
             createdAt: Date(timeIntervalSinceNow: -86400 * 3), updatedAt: Date(timeIntervalSinceNow: -86400 * 3)),
        Pick(id: "pick-5c", userID: thirdUserID, gameID: "game-5", groupID: "group-2",
             pickedTeam: "France", isSuperdog: false, result: .win,
             createdAt: Date(timeIntervalSinceNow: -86400 * 3), updatedAt: Date(timeIntervalSinceNow: -86400 * 3)),

        // game-6 Brazil -1.5 won 3-1 (covered)
        Pick(id: "pick-6a", userID: currentUserID, gameID: "game-6", groupID: "group-2",
             pickedTeam: "Brazil", isSuperdog: false, result: .win,
             createdAt: Date(timeIntervalSinceNow: -86400 * 2), updatedAt: Date(timeIntervalSinceNow: -86400 * 2)),
        Pick(id: "pick-6b", userID: otherUserID, gameID: "game-6", groupID: "group-2",
             pickedTeam: "Brazil", isSuperdog: false, result: .win,
             createdAt: Date(timeIntervalSinceNow: -86400 * 2), updatedAt: Date(timeIntervalSinceNow: -86400 * 2)),
        Pick(id: "pick-6c", userID: thirdUserID, gameID: "game-6", groupID: "group-2",
             pickedTeam: "Croatia", isSuperdog: false, result: .loss,
             createdAt: Date(timeIntervalSinceNow: -86400 * 2), updatedAt: Date(timeIntervalSinceNow: -86400 * 2)),

        // Alice has picked US for the upcoming game-7
        Pick(id: "pick-7", userID: currentUserID, gameID: "game-7", groupID: "group-2",
             pickedTeam: "United States", isSuperdog: false, result: .pending,
             createdAt: Date(timeIntervalSinceNow: -3600), updatedAt: Date(timeIntervalSinceNow: -3600))
    ]

    // MARK: - Standings
    //
    // NFL (group-1): derived from all finalized picks above
    //   Alice:   3W  1L  1SD  (superdog win = +3; effective 6W) → win%  6/7  ≈ 85.7%
    //   Bob:     2W  3L  0SD                                    → win%  2/5  = 40.0%
    //   Charlie: 2W  3L  0SD  (same record, Bob wins tiebreak by alpha-sort in UI)
    //
    // World Cup (group-2): derived from game-5 and game-6
    //   Alice:   2W  0L → 100%
    //   Bob:     1W  1L →  50%
    //   Charlie: 1W  1L →  50% (Bob wins tiebreak via total wins, both equal here — display order is stable)
    static let standings: [Standing] = [
        // NFL standings
        Standing(userID: currentUserID, groupID: "group-1", displayName: "Alice",
                 wins: 3, losses: 1, superdogWins: 1, superdogsUsed: 1,
                 updatedAt: Date(timeIntervalSinceNow: -3600)),
        Standing(userID: otherUserID, groupID: "group-1", displayName: "Bob",
                 wins: 2, losses: 3, superdogWins: 0, superdogsUsed: 0,
                 updatedAt: Date(timeIntervalSinceNow: -3600)),
        Standing(userID: thirdUserID, groupID: "group-1", displayName: "Charlie",
                 wins: 2, losses: 3, superdogWins: 0, superdogsUsed: 0,
                 updatedAt: Date(timeIntervalSinceNow: -3600)),
        // World Cup standings
        Standing(userID: currentUserID, groupID: "group-2", displayName: "Alice",
                 wins: 2, losses: 0, superdogWins: 0, superdogsUsed: 0,
                 updatedAt: Date(timeIntervalSinceNow: -86400)),
        Standing(userID: otherUserID, groupID: "group-2", displayName: "Bob",
                 wins: 1, losses: 1, superdogWins: 0, superdogsUsed: 0,
                 updatedAt: Date(timeIntervalSinceNow: -86400)),
        Standing(userID: thirdUserID, groupID: "group-2", displayName: "Charlie",
                 wins: 1, losses: 1, superdogWins: 0, superdogsUsed: 0,
                 updatedAt: Date(timeIntervalSinceNow: -86400))
    ]
}
