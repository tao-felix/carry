import AppKit

/// A luggage tag, drawn as a template image so it follows the menu bar's light/dark rendering.
/// While a sync runs, a small dot sits at the bottom-right, separated from the tag by a cleared ring.
enum MenuBarIcon {
    static let idle = make(syncing: false)
    static let syncing = make(syncing: true)

    static func image(syncing: Bool) -> NSImage { syncing ? self.syncing : idle }

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

    private static func make(syncing: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setFillColor(NSColor.black.cgColor)

            // Tag body: a rounded rectangle whose top end tapers to a flat tip, hung at an angle.
            ctx.saveGState()
            ctx.translateBy(x: 8.6, y: 9)
            ctx.rotate(by: -.pi / 5.5)
            let body = CGMutablePath()
            body.move(to: CGPoint(x: -4, y: -5.6))
            body.addArc(tangent1End: CGPoint(x: -4, y: -7.6), tangent2End: CGPoint(x: -2, y: -7.6), radius: 1.6)
            body.addLine(to: CGPoint(x: 2, y: -7.6))
            body.addArc(tangent1End: CGPoint(x: 4, y: -7.6), tangent2End: CGPoint(x: 4, y: -5.6), radius: 1.6)
            body.addLine(to: CGPoint(x: 4, y: 3.2))
            body.addLine(to: CGPoint(x: 1.6, y: 7.4))
            body.addLine(to: CGPoint(x: -1.6, y: 7.4))
            body.addLine(to: CGPoint(x: -4, y: 3.2))
            body.closeSubpath()
            ctx.addPath(body)
            ctx.fillPath()
            // The hole the strap goes through.
            ctx.setBlendMode(.clear)
            ctx.fillEllipse(in: CGRect(x: -1.3, y: 3.2, width: 2.6, height: 2.6))
            ctx.setBlendMode(.normal)
            ctx.restoreGState()

            if syncing {
                ctx.setBlendMode(.clear)
                ctx.fillEllipse(in: CGRect(x: 10.2, y: -0.8, width: 8.6, height: 8.6))
                ctx.setBlendMode(.normal)
                ctx.fillEllipse(in: CGRect(x: 12, y: 1, width: 5, height: 5))
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
