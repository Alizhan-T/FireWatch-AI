import Foundation
import UserNotifications
import UIKit

/// Only local iPhone notifications for deliberate, user-initiated test events.
/// No APNs/Firebase credentials, no backend, no 112 call and no real SOS dispatch.
@MainActor
enum DemoSOSNotifications {
    static let category = "FIREWATCH_DEMO_TRAINING"

    static func schedule(for event: LocalFireEvent) async -> String {
        guard event.isSimulation else {
            return "Уведомление SOS доступно только в учебном DEMO-режиме."
        }
        let center = UNUserNotificationCenter.current()
        do {
            let settings = await center.notificationSettings()
            var allowed = settings.authorizationStatus == .authorized ||
                          settings.authorizationStatus == .provisional
            if settings.authorizationStatus == .notDetermined {
                allowed = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            }
            guard allowed else {
                return "Уведомления отключены. Разрешите их для FireWatch AI в настройках iPhone, чтобы получать DEMO SOS."
            }
            let content = UNMutableNotificationContent()
            content.title = "SOS · ДЕМО · УЧЕБНАЯ ТРЕВОГА"
            content.body = "Симуляция: \(event.kind.lowercased()) · \(event.city.name). Это не реальный пожар. Никто не вызван."
            content.sound = .default
            content.categoryIdentifier = category
            content.userInfo = ["firewatch_demo": true, "event_id": event.id.uuidString]
            let request = UNNotificationRequest(
                identifier: "firewatch.demo.\(event.id.uuidString).\(UUID().uuidString)",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
            )
            try await center.add(request)
            return "SOS · DEMO запланировано на этом iPhone. Это только тестовое уведомление."
        } catch {
            return "Не удалось показать DEMO-уведомление: \(error.localizedDescription)"
        }
    }
}

/// Local notifications are displayed in the foreground as well; this is NOT
/// remote push and does not require a paid Apple Developer Program membership.
final class FireWatchLocalNotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if notification.request.content.categoryIdentifier == DemoSOSNotifications.category {
            completionHandler([.banner, .list, .sound])
        } else {
            completionHandler([])
        }
    }
}
