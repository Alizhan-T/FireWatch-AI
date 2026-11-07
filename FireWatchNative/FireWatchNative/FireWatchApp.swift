import SwiftUI

@main
struct FireWatchApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup { MainView() }
    }
}
