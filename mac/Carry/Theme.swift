import AppKit
import SwiftUI

// MARK: - Palette (docs/DESIGN.md)

/// Paper/ink with two channel colors and one accent. Light and dark in one token.
enum Theme {
    static let paper = Color(light: 0xF6F1E9, dark: 0x141310)
    static let paper2 = Color(light: 0xEDE6DA, dark: 0x1F1D18)
    static let line = Color(light: 0xD9D0C1, dark: 0x2E2B24)
    static let ink = Color(light: 0x141310, dark: 0xF6F1E9)
    static let ink2 = Color(light: 0x5C574D, dark: 0xA39D90)
    /// iCloud channel: Apple already syncs it.
    static let moss = Color(light: 0x2E5E4E, dark: 0x7FB39E)
    /// Carry app channel; also the one accent.
    static let tangerine = Color(light: 0xE8562B, dark: 0xFF7A4D)
    static let ok = moss
    static let warn = Color(light: 0xB8860B, dark: 0xE0B54A)
    /// Text on a tangerine fill.
    static let onAccent = Color(light: 0xF6F1E9, dark: 0x141310)

    static func color(for channel: Channel) -> Color { channel == .icloud ? moss : tangerine }
}

/// The same tokens where AppKit needs an NSColor (window background).
enum NSTheme {
    static let paper = NSColor(light: 0xF6F1E9, dark: 0x141310)
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(light: light, dark: dark))
    }
}

extension NSColor {
    /// A dynamic color that follows the effective appearance (light / dark, including per-window overrides).
    convenience init(light: UInt32, dark: UInt32) {
        self.init(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(rgb: isDark ? dark : light)
        }
    }

    convenience init(rgb: UInt32) {
        self.init(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}

// MARK: - Type

/// macOS point sizes. Serif (New York) for titles, SF for text, SF Mono for paths, commands and times.
extension Font {
    static let screenTitle = Font.system(size: 32, weight: .regular, design: .serif)
    static let lede = Font.system(size: 17, weight: .regular, design: .serif)
    static let sectionHead = Font.system(size: 19, weight: .regular, design: .serif)
    static let bodyText = Font.system(size: 13)
    static let bodyMedium = Font.system(size: 13, weight: .medium)
    static let small = Font.system(size: 11.5)
    static let mono = Font.system(size: 11.5, design: .monospaced)
    static let monoSmall = Font.system(size: 10, design: .monospaced)
}
