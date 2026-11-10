import SwiftUI

@main
struct FireWatchApp: App {
    // Foreground local SOS-DEMO banners; no APNs / Personal Team entitlement needed.
    @UIApplicationDelegateAdaptor(FireWatchLocalNotificationDelegate.self) private var notificationDelegate
    var body: some Scene {
        WindowGroup { MainView() }
    }
}
