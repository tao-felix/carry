import Foundation

/// DEBUG-only launch arguments, so every screen can be reached and screenshotted in a simulator:
///   `-carryScreen welcome|sources|home|pro|settings`  open that screen (implies demo data)
///   `-carryDemo 1`                                    seed demo data without choosing a screen
///   `-carryICloudOff 1`                               preview the "iCloud Drive is off" state
///   `-carryScroll bottom`                             scroll the screen to its end (lower-half screenshots)
///   `-carryE2E 1`                                     exercise the real writers for an end-to-end test with the Mac CLI
/// Release builds ignore all of them.
enum LaunchOptions {
    #if DEBUG
    static let screen: String? = UserDefaults.standard.string(forKey: "carryScreen")
    static let demo: Bool = screen != nil || UserDefaults.standard.bool(forKey: "carryDemo")
    static let icloudOff: Bool = UserDefaults.standard.bool(forKey: "carryICloudOff")
    static let scrollToBottom: Bool = UserDefaults.standard.string(forKey: "carryScroll") == "bottom"
    /// `-carryE2E 1`: drive the REAL writers (sources.json, inbox, manifest, sync) so the Mac CLI can be tested against this container.
    static let e2e: Bool = UserDefaults.standard.bool(forKey: "carryE2E")
    #else
    static let screen: String? = nil
    static let demo = false
    static let icloudOff = false
    static let scrollToBottom = false
    static let e2e = false
    #endif

    static var forceWelcome: Bool { screen == "welcome" }
    static var initialTab: Tab { screen.flatMap(Tab.init(rawValue:)) ?? .home }
}
