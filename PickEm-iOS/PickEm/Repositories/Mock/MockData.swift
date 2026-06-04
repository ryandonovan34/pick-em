import Foundation

// Shared in-memory mock data used by all LocalMockRepository implementations.
enum MockData {
    static let currentUserID = "user-1"
    static let otherUserID = "user-2"
    static let adminUserID = "user-1"

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
        Game(
            id: "game-6",
            weekID: "week-2",
            oddsAPIID: "odds-6",
            sport: .worldCup,
            homeTeam: "Brazil",
            awayTeam: "Croatia",
            spread: -1.5,
            favoriteTeam: "Brazil",
            kickoffAt: Date(timeIntervalSinceNow: -86400 * 1),
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
    static var games: [Game] { nflGames + worldCupGames }

    static let picks: [Pick] = [
        // NFL picks
        Pick(
            id: "pick-1",
            userID: currentUserID,
            gameID: "game-1",
            groupID: "group-1",
            pickedTeam: "Kansas City Chiefs",
            isSuperdog: false,
            result: .pending,
            createdAt: Date(timeIntervalSinceNow: -3600),
            updatedAt: Date(timeIntervalSinceNow: -3600)
        ),
        Pick(
            id: "pick-2",
            userID: currentUserID,
            gameID: "game-4",
            groupID: "group-1",
            pickedTeam: "Buffalo Bills",
            isSuperdog: false,
            result: .win,
            createdAt: Date(timeIntervalSinceNow: -86400),
            updatedAt: Date(timeIntervalSinceNow: -86400)
        ),
        Pick(
            id: "pick-3",
            userID: otherUserID,
            gameID: "game-4",
            groupID: "group-1",
            pickedTeam: "Miami Dolphins",
            isSuperdog: false,
            result: .loss,
            createdAt: Date(timeIntervalSinceNow: -86400),
            updatedAt: Date(timeIntervalSinceNow: -86400)
        ),
        // World Cup picks
        Pick(
            id: "pick-4",
            userID: currentUserID,
            gameID: "game-5",
            groupID: "group-2",
            pickedTeam: "France",
            isSuperdog: false,
            result: .win,
            createdAt: Date(timeIntervalSinceNow: -86400 * 3),
            updatedAt: Date(timeIntervalSinceNow: -86400 * 3)
        ),
        Pick(
            id: "pick-5",
            userID: otherUserID,
            gameID: "game-5",
            groupID: "group-2",
            pickedTeam: "Morocco",
            isSuperdog: false,
            result: .loss,
            createdAt: Date(timeIntervalSinceNow: -86400 * 3),
            updatedAt: Date(timeIntervalSinceNow: -86400 * 3)
        ),
        Pick(
            id: "pick-6",
            userID: currentUserID,
            gameID: "game-7",
            groupID: "group-2",
            pickedTeam: "United States",
            isSuperdog: false,
            result: .pending,
            createdAt: Date(timeIntervalSinceNow: -3600),
            updatedAt: Date(timeIntervalSinceNow: -3600)
        )
    ]

    static let standings: [Standing] = [
        // NFL standings
        Standing(
            userID: currentUserID,
            groupID: "group-1",
            displayName: "Alice",
            wins: 7,
            losses: 3,
            superdogWins: 1,
            superdogsUsed: 1,
            updatedAt: Date(timeIntervalSinceNow: -3600)
        ),
        Standing(
            userID: otherUserID,
            groupID: "group-1",
            displayName: "Bob",
            wins: 6,
            losses: 4,
            superdogWins: 0,
            superdogsUsed: 0,
            updatedAt: Date(timeIntervalSinceNow: -3600)
        ),
        // World Cup standings
        Standing(
            userID: currentUserID,
            groupID: "group-2",
            displayName: "Alice",
            wins: 2,
            losses: 0,
            superdogWins: 0,
            superdogsUsed: 0,
            updatedAt: Date(timeIntervalSinceNow: -86400)
        ),
        Standing(
            userID: otherUserID,
            groupID: "group-2",
            displayName: "Bob",
            wins: 0,
            losses: 2,
            superdogWins: 0,
            superdogsUsed: 0,
            updatedAt: Date(timeIntervalSinceNow: -86400)
        )
    ]
}
