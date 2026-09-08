import AppKit

/// The Carry mark for the menu bar: an italic C carrying a dot, shipped as template images in the
/// asset catalog so they follow the menu bar's light/dark rendering.
/// While a sync runs the dot is away (the C alone), which reads as "carrying".
enum MenuBarIcon {
    static let idle = load("MenuBarIdle")
    static let syncing = load("MenuBarSyncing")

    static func image(syncing: Bool) -> NSImage { syncing ? self.syncing : idle }

    private static func load(_ name: String) -> NSImage {
        let image = NSImage(named: name) ?? NSImage(size: NSSize(width: 18, height: 18))
        image.isTemplate = true
        return image
    }

    #if DEBUG
    /// Both icons at 6×, black on paper, for eyeballing the shape.
    static func writeDebugPNG(to path: String) {
        let scale: CGFloat = 6
        let canvas = NSImage(size: NSSize(width: 18 * scale * 2 + 30, height: 18 * scale + 20), flipped: false) { rect in
            NSColor(rgb: 0xF6F1E9).setFill()
            rect.fill()
            for (index, icon) in [idle, syncing].enumerated() {
                let origin = CGPoint(x: 10 + CGFloat(index) * (18 * scale + 10), y: 10)
                icon.draw(in: CGRect(origin: origin, size: CGSize(width: 18 * scale, height: 18 * scale)),
                          from: .zero, operation: .sourceOver, fraction: 1)
            }
            return true
        }
        guard let tiff = canvas.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }
    #endif
}
