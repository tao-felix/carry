import AppKit
import SwiftUI

/// The one main window, 720×640 on paper, opened from the menu bar ("Open Carry") or at launch when needed.
@MainActor
final class MainWindowController {
    static let shared = MainWindowController()
    static let contentSize = NSSize(width: 720, height: 640)

    private(set) var window: NSWindow?

    func show(model: AppModel) {
        if window == nil { window = makeWindow(model: model) }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        // No control takes keyboard focus on open, so nothing scrolls into view uninvited.
        window?.makeFirstResponder(nil)
    }

    private func makeWindow(model: AppModel) -> NSWindow {
        let hosting = NSHostingController(rootView: MainView(model: model))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Carry"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = NSTheme.paper
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.setContentSize(Self.contentSize)
        window.initialFirstResponder = nil
        window.setFrameAutosaveName("CarryMain")
        if !window.setFrameUsingName("CarryMain") { window.center() }
        return window
    }

    /// DEBUG: scroll the main scroll view to its end so the lower half can be snapshotted.
    func scrollToBottom() {
        guard let root = window?.contentView, let scrollView = Self.firstScrollView(in: root),
              let document = scrollView.documentView else { return }
        let clip = scrollView.contentView
        let y = document.isFlipped ? document.bounds.height - clip.bounds.height : 0
        clip.scroll(to: NSPoint(x: 0, y: max(0, y)))
        scrollView.reflectScrolledClipView(clip)
    }

    private static func firstScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView { return scrollView }
        for child in view.subviews {
            if let found = firstScrollView(in: child) { return found }
        }
        return nil
    }

    /// DEBUG: render the content view to a PNG (no screen-recording permission needed).
    func snapshot(to path: String) {
        guard let view = window?.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
    }
}
