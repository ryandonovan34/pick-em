import SwiftUI
import FirebaseMessaging
import FirebaseCore

@main
struct PickEmApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var dependencies = AppDependencies()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(dependencies)
                .tint(AdaptiveColor.pePrimaryFill)
                .task {
                    appDelegate.configure(with: dependencies.notificationService)
                    await dependencies.notificationService.requestAuthorization()
                }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    private var notificationService: NotificationService?

    func configure(with service: NotificationService) {
        notificationService = service
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()
        Messaging.messaging().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            notificationService?.handleAPNSToken(deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            notificationService?.handleAPNSRegistrationFailure(error)
        }
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        Task { @MainActor in
            notificationService?.handleSilentPush(userInfo)
        }
        completionHandler(.newData)
    }
}

extension AppDelegate: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        Task { @MainActor in
            notificationService?.handleFCMRegistrationToken(fcmToken)
        }
    }
}
