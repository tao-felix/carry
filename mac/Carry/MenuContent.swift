import AppKit
import SwiftUI

/// The menu under the menu bar tag: status, Sync now, Open Carry, Open context folder, Quit.
struct MenuContent: View {
    let model: AppModel

    var body: some View {
        Text(model.statusLine.text)
        Divider()
        Button("Sync now") { Task { await model.sync(reason: "menu") } }
            .disabled(model.isSyncing || model.cliPath == nil)
        Button("Open Carry") { MainWindowController.shared.show(model: model) }
        Button("Open context folder") { model.openContextFolder() }
        Divider()
        Button("Quit Carry") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

/// The menu bar item itself: the tag, with a dot while a sync runs.
struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        Image(nsImage: MenuBarIcon.image(syncing: model.isSyncing))
    }
}
