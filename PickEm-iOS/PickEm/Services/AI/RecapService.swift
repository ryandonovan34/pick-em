import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Generates a short, on-device recap of a group's week using Apple's
/// Foundation Models framework (iOS 26+, Apple Intelligence-eligible
/// devices only — A17 Pro / 8GB RAM). Purely cosmetic flavor text layered
/// on top of data the app has already computed; never touches picks,
/// grading, or standings math.
enum RecapService {
    struct RecapUnavailable: Error, LocalizedError {
        let reason: String
        var errorDescription: String? { reason }
    }

    /// Pure, synchronous, no FoundationModels dependency — the only part of
    /// this feature that's meaningfully unit-testable. Summarizes final
    /// scores, each member's result per game, and current standings.
    static func buildPrompt(games: [Game], memberPicks: [String: [Pick]], standings: [Standing]) -> String {
        let displayNames = Dictionary(uniqueKeysWithValues: standings.map { ($0.userID, $0.displayName) })
        let finalGames = games.filter { $0.resultPosted }

        var lines: [String] = ["This week's results:"]
        for game in finalGames {
            guard let homeScore = game.homeScore, let awayScore = game.awayScore else { continue }
            lines.append("- \(game.awayTeam) \(awayScore) @ \(game.homeTeam) \(homeScore) (spread: \(game.spreadDisplay))")

            for pick in memberPicks[game.id] ?? [] {
                let name = displayNames[pick.userID] ?? "A member"
                let outcome: String
                switch pick.result {
                case .win: outcome = "won"
                case .superdogWin: outcome = "hit a superdog win"
                case .loss: outcome = pick.isForfeit ? "forgot to pick and took an automatic loss" : "lost"
                case .pending: outcome = "is still pending"
                }
                lines.append("  \(name) picked \(pick.pickedTeam) and \(outcome).")
            }
        }

        if !standings.isEmpty {
            lines.append("")
            lines.append("Current standings:")
            for standing in standings.sorted(by: { $0.winPercentage > $1.winPercentage }) {
                let pct = String(format: "%.1f", standing.winPercentage * 100)
                lines.append("- \(standing.displayName): \(standing.record) (\(pct)%)")
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Synchronous best-effort check for whether the recap feature should be
    /// offered at all — lets the UI decide whether to show the card at all
    /// before attempting a full generation.
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { return false }
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
        #else
        return false
        #endif
    }

    /// Requires iOS 26+ and an Apple Intelligence-eligible device. Throws
    /// RecapUnavailable otherwise — callers should hide the recap UI
    /// entirely rather than surface an error to the user.
    static func generateRecap(games: [Game], memberPicks: [String: [Pick]], standings: [Standing]) async throws -> String {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else {
            throw RecapUnavailable(reason: "Requires iOS 26 or later.")
        }
        guard case .available = SystemLanguageModel.default.availability else {
            throw RecapUnavailable(reason: "Apple Intelligence isn't available on this device.")
        }

        let session = LanguageModelSession(
            instructions: """
            You are a witty pick'em league commissioner writing a short weekly recap \
            for a group chat of friends. Write 2-3 sentences, good-natured trash talk \
            is welcome, mention at least one member by name, and keep it PG. Do not \
            invent any facts beyond what's given to you.
            """
        )
        let prompt = buildPrompt(games: games, memberPicks: memberPicks, standings: standings)
        let response = try await session.respond(to: prompt)
        return response.content
        #else
        throw RecapUnavailable(reason: "Foundation Models isn't available in this build.")
        #endif
    }
}
