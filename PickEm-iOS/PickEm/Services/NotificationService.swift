import Foundation
import FirebaseMessaging
import UserNotifications
import UIKit

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

    /// Forward the raw APNs device token to Firebase so it can issue an FCM registration token.
    func handleAPNSToken(_ deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    /// Upload the FCM registration token to the backend. Called by MessagingDelegate.
    func uploadFCMToken(_ token: String) {
        Task {
            try? await authRepository?.updateFCMToken(token)
        }
    }

    /// Proactively re-upload the current FCM token. Notification permission is
    /// requested unconditionally at app launch (PickEmApp), independent of auth
    /// state — on a fresh install the APNs/FCM handshake can complete in under a
    /// second, well before a human finishes the login/register form, so
    /// MessagingDelegate can hand back a token while tokenStore has no access
    /// token yet. uploadFCMToken's PUT then goes out with no Authorization
    /// header, the backend 401s, and `try?` swallows it silently with no retry.
    /// Called whenever the authenticated main content appears (RootView) —
    /// covers that race and self-heals any other reason a prior upload failed.
    func uploadCurrentTokenIfAvailable() {
        Messaging.messaging().token { [weak self] token, error in
            guard let token, error == nil else { return }
            Task { @MainActor in
                self?.uploadFCMToken(token)
            }
        }
    }

    /// Handle a silent FCM data push. Invalidates the relevant cache scope.
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
