import Foundation
import Combine
import UIKit
import UserNotifications

@MainActor
final class PushManager: ObservableObject {
    static let shared = PushManager()

    @Published private(set) var fcmToken = UserDefaults.standard.string(forKey: "firewatch.fcmToken")
    @Published private(set) var status = "Push не настроен"

    private init() {}

    func setStatus(_ value: String) { status = value }

    func updateToken(_ token: String) {
        fcmToken = token
        status = "Устройство зарегистрировано в Firebase"
        UserDefaults.standard.set(token, forKey: "firewatch.fcmToken")
    }

    func requestPermission() async {
        guard AppDelegate.firebaseConfigured else {
            status = "Добавьте GoogleService-Info.plist из Firebase Console"
            return
        }
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            guard granted else {
                status = "Разрешение на уведомления отклонено в настройках iPhone"
                return
            }
            UIApplication.shared.registerForRemoteNotifications()
            status = "Запрошена регистрация push-уведомлений…"
        } catch {
            status = "Не удалось запросить уведомления: \(error.localizedDescription)"
        }
    }
}
