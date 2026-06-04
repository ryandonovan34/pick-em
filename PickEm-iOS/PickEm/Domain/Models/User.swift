import Foundation

struct User: Identifiable, Equatable {
    let id: String
    let email: String
    let displayName: String
    var fcmToken: String?
    let createdAt: Date
}
