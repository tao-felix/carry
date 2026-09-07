import AppKit
import SwiftUI

@main
struct CarryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = AppModel.shared
        #if DEBUG
        DebugArguments.applyAppearance()
        model.previewMode = DebugArguments.previewMode
        model.noProcess = UserDefaults.standard.bool(forKey: "carryNoProcess")
        model.syncAndQuit = UserDefaults.standard.bool(forKey: "carrySyncAndQuit")
        #endif
        model.start()
        if model.shouldOpenWindowAtLaunch { MainWindowController.shared.show(model: model) }
        #if DEBUG
        DebugArguments.scheduleSnapshot(model: model)
        #endif
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainWindowController.shared.show(model: AppModel.shared)
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.stop()
    }
}

#if DEBUG
/// Launch arguments (see project.yml): `-carryAppearance dark`, `-carryPreview 1`, `-carryScroll bottom`,
/// `-carrySnapshot /path.png` (written `-carrySnapshotDelay` seconds after launch, default 3; needs no
/// screen-recording permission); `-carryNoProcess 1` skips OCR / transcription, `-carrySyncAndQuit 1` syncs once
/// and exits (scripted parity runs, with `CARRY_HOME` pointing at a scratch home).
@MainActor
enum DebugArguments {
    static var previewMode: Bool { UserDefaults.standard.bool(forKey: "carryPreview") }

    static func applyAppearance() {
        switch UserDefaults.standard.string(forKey: "carryAppearance") {
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        default: break
        }
    }

    static func scheduleSnapshot(model: AppModel) {
        guard let path = UserDefaults.standard.string(forKey: "carrySnapshot"), !path.isEmpty else { return }
        let delay = UserDefaults.standard.double(forKey: "carrySnapshotDelay")
        let toBottom = UserDefaults.standard.string(forKey: "carryScroll") == "bottom"
        MainWindowController.shared.show(model: model)
        // An accessory app launched from a script is not activated, so its controls would render inactive.
        NSApp.perform(NSSelectorFromString("activateIgnoringOtherApps:"), with: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + (delay > 0 ? delay : 3)) {
            MainWindowController.shared.window?.makeKeyAndOrderFront(nil)
            if toBottom { MainWindowController.shared.scrollToBottom() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                MainWindowController.shared.snapshot(to: path)
                MenuBarIcon.writeDebugPNG(to: path.replacingOccurrences(of: ".png", with: "-icon.png"))
                AppLog.write("snapshot \(path) key=\(MainWindowController.shared.window?.isKeyWindow ?? false) "
                             + "windows=\(NSApp.windows.map { String(describing: type(of: $0)) })")
            }
        }
    }
}
#endif
