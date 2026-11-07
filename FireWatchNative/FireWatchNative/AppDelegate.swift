import UIKit
import UserNotifications
import FirebaseCore
import FirebaseMessaging

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate, MessagingDelegate, UNUserNotificationCenterDelegate {
    static var firebaseConfigured = false

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        guard Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil else {
            PushManager.shared.setStatus("Firebase не настроен: добавьте GoogleService-Info.plist")
            return true
        }

        FirebaseApp.configure()
        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self
        Self.firebaseConfigured = true
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        PushManager.shared.setStatus("APNs registration failed: \(error.localizedDescription)")
    }

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken, !fcmToken.isEmpty else { return }
        Task { @MainActor in
            PushManager.shared.updateToken(fcmToken)
            NotificationCenter.default.post(name: .fireWatchFCMTokenUpdated, object: fcmToken)
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let incidentID = response.notification.request.content.userInfo["incident_id"] as? String {
            NotificationCenter.default.post(
                name: .fireWatchOpenIncident,
                object: nil,
                userInfo: ["incident_id": incidentID]
            )
        }
        completionHandler()
    }
}

extension Notification.Name {
    static let fireWatchFCMTokenUpdated = Notification.Name("FireWatchFCMTokenUpdated")
    static let fireWatchOpenIncident = Notification.Name("FireWatchOpenIncident")
}
