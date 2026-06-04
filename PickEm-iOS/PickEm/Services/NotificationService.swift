import Foundation
import UIKit
import UserNotifications

@MainActor
final class NotificationService: NSObject {
    private var authRepository: (any AuthRepositoryProtocol)?
    private let cacheService: LocalCacheService

    init(authRepository: any AuthRepositoryProtocol, cacheService: LocalCacheService) {
        self.authRepository = authRepository
        self.cacheService = cacheService
    }

    func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        guard granted else { return }
        await MainActor.run {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    func handleDeviceToken(_ deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task {
            try? await authRepository?.updateFCMToken(tokenString)
        }
    }

    /// Handle a silent FCM data push. Invalidates the relevant cache scope and returns it for callers that need to trigger a re-fetch.
    @discardableResult
    func handleSilentPush(_ userInfo: [AnyHashable: Any]) -> CacheScope? {
        guard let type = userInfo["type"] as? String else { return nil }
        let scope: CacheScope?
        switch type {
        case "slate_finalized":
            guard let groupID = userInfo["group_id"] as? String,
                  let weekID = userInfo["week_id"] as? String else { return nil }
            scope = .slate(groupID: groupID, weekID: weekID)
        case "results_posted":
            guard let groupID = userInfo["group_id"] as? String else { return nil }
            scope = .results(groupID: groupID)
        default:
            scope = nil
        }
        if let scope {
            cacheService.invalidate(scope: scope)
        }
        return scope
    }
}
