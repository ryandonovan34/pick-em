import Foundation
import SwiftData

enum CacheScope {
    case slate(groupID: String, weekID: String)
    case standings(groupID: String)
    case results(groupID: String)  // clears games + standings for a group (used on results_posted FCM)
    case all
}

@MainActor
final class LocalCacheService {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    convenience init() throws {
        let schema = Schema([CachedGame.self, CachedPick.self, CachedStanding.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        let container = try ModelContainer(for: schema, configurations: config)
        self.init(container: container)
    }

    var context: ModelContext { container.mainContext }

    // MARK: - Invalidation

    func invalidate(scope: CacheScope) {
        switch scope {
        case .slate(let groupID, let weekID):
            let predicate = #Predicate<CachedGame> { $0.groupID == groupID && $0.weekID == weekID }
            try? context.delete(model: CachedGame.self, where: predicate)
        case .standings(let groupID):
            let predicate = #Predicate<CachedStanding> { $0.groupID == groupID }
            try? context.delete(model: CachedStanding.self, where: predicate)
        case .results(let groupID):
            let gamePredicate = #Predicate<CachedGame> { $0.groupID == groupID }
            try? context.delete(model: CachedGame.self, where: gamePredicate)
            let standingPredicate = #Predicate<CachedStanding> { $0.groupID == groupID }
            try? context.delete(model: CachedStanding.self, where: standingPredicate)
        case .all:
            try? context.delete(model: CachedGame.self)
            try? context.delete(model: CachedPick.self)
            try? context.delete(model: CachedStanding.self)
        }
        try? context.save()
    }

    // MARK: - Games

    func saveGames(_ games: [Game], groupID: String, weekID: String) {
        guard let data = try? JSONEncoder().encode(games) else { return }
        let predicate = #Predicate<CachedGame> { $0.groupID == groupID && $0.weekID == weekID }
        try? context.delete(model: CachedGame.self, where: predicate)
        context.insert(CachedGame(id: "\(groupID)|\(weekID)", weekID: weekID, groupID: groupID, data: data))
        try? context.save()
    }

    func loadGames(groupID: String, weekID: String) -> [Game]? {
        let predicate = #Predicate<CachedGame> { $0.groupID == groupID && $0.weekID == weekID }
        guard let entry = try? context.fetch(FetchDescriptor<CachedGame>(predicate: predicate)).first,
              let games = try? JSONDecoder().decode([Game].self, from: entry.data) else { return nil }
        return games
    }

    // MARK: - Standings

    func saveStandings(_ standings: [Standing], groupID: String) {
        guard let data = try? JSONEncoder().encode(standings) else { return }
        let predicate = #Predicate<CachedStanding> { $0.groupID == groupID }
        try? context.delete(model: CachedStanding.self, where: predicate)
        context.insert(CachedStanding(id: groupID, groupID: groupID, data: data))
        try? context.save()
    }

    func loadStandings(groupID: String) -> [Standing]? {
        let predicate = #Predicate<CachedStanding> { $0.groupID == groupID }
        guard let entry = try? context.fetch(FetchDescriptor<CachedStanding>(predicate: predicate)).first,
              let standings = try? JSONDecoder().decode([Standing].self, from: entry.data) else { return nil }
        return standings
    }
}

// MARK: - SwiftData models

@Model
final class CachedGame {
    @Attribute(.unique) var id: String
    var weekID: String
    var groupID: String
    var data: Data

    init(id: String, weekID: String, groupID: String, data: Data) {
        self.id = id
        self.weekID = weekID
        self.groupID = groupID
        self.data = data
    }
}

@Model
final class CachedPick {
    @Attribute(.unique) var id: String
    var gameID: String
    var groupID: String
    var weekID: String
    var data: Data

    init(id: String, gameID: String, groupID: String, weekID: String, data: Data) {
        self.id = id
        self.gameID = gameID
        self.groupID = groupID
        self.weekID = weekID
        self.data = data
    }
}

@Model
final class CachedStanding {
    @Attribute(.unique) var id: String
    var groupID: String
    var data: Data

    init(id: String, groupID: String, data: Data) {
        self.id = id
        self.groupID = groupID
        self.data = data
    }
}
