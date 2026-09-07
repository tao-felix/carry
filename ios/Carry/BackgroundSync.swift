import BackgroundTasks
import Foundation

/// `app.carry.ios.sync`: an hourly BGAppRefreshTask. iOS runs it when it likes, and only an unlocked
/// phone can read Health, so this is "roughly hourly", never live (DATA-CONTRACT §4).
enum BackgroundSync {
    static let identifier = "app.carry.ios.sync"
    static let interval: TimeInterval = 3600

    static func register(_ work: @escaping () async -> Void) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            schedule()
            let job = Task {
                await work()
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = {
                job.cancel()
                task.setTaskCompleted(success: false)
            }
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
        // Throws in the simulator (unsupported); harmless.
        try? BGTaskScheduler.shared.submit(request)
    }
}
