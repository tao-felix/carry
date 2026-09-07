import SwiftUI
import UIKit

@main
struct CarryApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        ScreenDebug.scrollToBottom = LaunchOptions.scrollToBottom
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .task { await model.bootstrap() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await model.foreground() } }
                }
        }
    }
}

/// Registers the background refresh task before launch finishes, as BGTaskScheduler requires.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        BackgroundSync.register {
            await AppModel.shared.backgroundSync()
        }
        return true
    }
}
