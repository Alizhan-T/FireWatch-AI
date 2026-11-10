import Foundation
import UserNotifications
import UIKit

enum DemoSOSCategory {
    static let identifier = "FIREWATCH_DEMO_TRAINING"
}

/// Only local iPhone notifications for deliberate, user-initiated test events.
/// No APNs/Firebase credentials, no backend, no 112 call and no real SOS dispatch.
@MainActor
enum DemoSOSNotifications {
    static func content(for event: LocalFireEvent) -> UNMutableNotificationContent? {
        guard event.isSimulation else { return nil }
        let content = UNMutableNotificationContent()
        content.title = "SOS · ДЕМО · УЧЕБНАЯ ТРЕВОГА"
        content.body = "Симуляция: \(event.kind.lowercased()) · \(event.city.name). Это не реальный пожар. Никто не вызван."
        content.sound = .default
        content.categoryIdentifier = DemoSOSCategory.identifier
        content.userInfo = ["firewatch_demo": true, "event_id": event.id.uuidString]
        return content
    }

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
            guard let content = content(for: event) else {
                return "Нельзя отправить SOS для реального события без подтверждения."
            }
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
@MainActor
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
        if notification.request.content.categoryIdentifier == DemoSOSCategory.identifier {
            completionHandler([.banner, .list, .sound])
        } else {
            completionHandler([])
        }
    }
}
