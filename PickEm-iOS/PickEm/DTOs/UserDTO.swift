import Foundation

struct UserDTO: Codable {
    let id: String
    let email: String
    let displayName: String
    let fcmToken: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, email, fcmToken = "fcm_token", createdAt = "created_at"
        case displayName = "display_name"
    }

    func toDomain() -> User {
        User(
            id: id,
            email: email,
            displayName: displayName,
            fcmToken: fcmToken,
            createdAt: createdAt
        )
    }
}

struct AuthResponseDTO: Codable {
    let accessToken: String
    let refreshToken: String
    let user: UserDTO

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case user
    }
}

struct GroupDTO: Codable {
    let id: String
    let name: String
    let adminID: String
    let joinCode: String
    let sport: String
    let mode: String
    let seasonYear: Int?
    let blindPicks: Bool
    let superdogsEnabled: Bool
    let superdogsPerUser: Int
    let includePreseason: Bool
    let includePlayoffs: Bool
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, sport, mode
        case adminID = "admin_id"
        case joinCode = "join_code"
        case seasonYear = "season_year"
        case blindPicks = "blind_picks"
        case superdogsEnabled = "superdogs_enabled"
        case superdogsPerUser = "superdogs_per_user"
        case includePreseason = "include_preseason"
        case includePlayoffs = "include_playoffs"
        case createdAt = "created_at"
    }

    func toDomain() -> Group {
        Group(
            id: id,
            name: name,
            adminID: adminID,
            joinCode: joinCode,
            sport: Sport(rawValue: sport) ?? .nfl,
            mode: ChallengeMode(rawValue: mode) ?? .season,
            seasonYear: seasonYear,
            blindPicks: blindPicks,
            superdogsEnabled: superdogsEnabled,
            superdogsPerUser: superdogsPerUser,
            includePreseason: includePreseason,
            includePlayoffs: includePlayoffs,
            createdAt: createdAt
        )
    }
}
