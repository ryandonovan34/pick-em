import Foundation
import FirebaseMessaging
import UserNotifications
import UIKit
import OSLog

/// To watch this live: run from Xcode on a real device (not TestFlight, which
/// has no console access), then filter Xcode's console for "Notifications",
/// or in Console.app filter by subsystem "com.pickem" + category "Notifications".
@MainActor
final class NotificationService: NSObject {
    private var authRepository: (any AuthRepositoryProtocol)?
    private let cacheService: LocalCacheService
    private let logger = Logger(subsystem: "com.pickem", category: "Notifications")

    init(authRepository: any AuthRepositoryProtocol, cacheService: LocalCacheService) {
        self.authRepository = authRepository
        self.cacheService = cacheService
    }

    func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        logger.debug("① Requesting notification authorization...")
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            guard granted else {
                logger.warning("① User denied notification authorization — nothing downstream will fire.")
                return
            }
            logger.debug("① Authorization granted. Registering for remote notifications...")
            await MainActor.run {
                UIApplication.shared.registerForRemoteNotifications()
            }
        } catch {
            logger.error("① requestAuthorization threw: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Forward the raw APNs device token to Firebase so it can issue an FCM registration token.
    func handleAPNSToken(_ deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        logger.debug("② Received raw APNs device token (\(deviceToken.count) bytes): \(hex, privacy: .private). Forwarding to Firebase...")
        Messaging.messaging().apnsToken = deviceToken
    }

    func handleAPNSRegistrationFailure(_ error: Error) {
        logger.error("② didFailToRegisterForRemoteNotifications: \(error.localizedDescription, privacy: .public) — no APNs token, so Firebase can never issue an FCM token on this device/build.")
    }

    /// Called by MessagingDelegate whenever Firebase (re)issues a registration token.
    func handleFCMRegistrationToken(_ token: String?) {
        guard let token else {
            logger.warning("③ MessagingDelegate fired with a nil FCM token.")
            return
        }
        logger.debug("③ Received FCM registration token: \(token, privacy: .private). Uploading...")
        uploadFCMToken(token)
    }

    /// Upload the FCM registration token to the backend.
    func uploadFCMToken(_ token: String) {
        Task {
            do {
                try await authRepository?.updateFCMToken(token)
                logger.debug("④ Uploaded FCM token to backend successfully.")
            } catch {
                logger.error("④ Failed to upload FCM token to backend: \(error.localizedDescription, privacy: .public) — likely no access token yet (not logged in). Should self-heal via uploadCurrentTokenIfAvailable() after login.")
            }
        }
    }

    /// Proactively re-upload the current FCM token. Notification permission is
    /// requested unconditionally at app launch (PickEmApp), independent of auth
    /// state — on a fresh install the APNs/FCM handshake can complete in under a
    /// second, well before a human finishes the login/register form, so
    /// MessagingDelegate can hand back a token while tokenStore has no access
    /// token yet. uploadFCMToken's PUT then goes out with no Authorization
    /// header, the backend 401s, and the failure above self-explains why.
    /// Called whenever the authenticated main content appears (RootView) —
    /// covers that race and self-heals any other reason a prior upload failed.
    func uploadCurrentTokenIfAvailable() {
        logger.debug("⑤ Authenticated screen appeared — fetching current FCM token to (re-)upload...")
        Messaging.messaging().token { [weak self] token, error in
            if let error {
                self?.logger.error("⑤ Messaging.token(completion:) failed: \(error.localizedDescription, privacy: .public)")
                return
            }
            guard let token else {
                self?.logger.warning("⑤ Messaging.token(completion:) returned no token and no error.")
                return
            }
            Task { @MainActor in
                self?.uploadFCMToken(token)
            }
        }
    }

    /// Handle a silent FCM data push. Invalidates the relevant cache scope.
    @discardableResult
    func handleSilentPush(_ userInfo: [AnyHashable: Any]) -> CacheScope? {
        logger.debug("Received silent push: \(String(describing: userInfo), privacy: .public)")
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
