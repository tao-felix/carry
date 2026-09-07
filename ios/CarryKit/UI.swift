import SwiftUI
import UIKit

// MARK: - Palette (DESIGN.md)

/// Paper/ink with two channel colors and one accent. Light and dark in one token.
public enum Theme {
    public static let paper = Color(light: 0xF6F1E9, dark: 0x141310)
    public static let paper2 = Color(light: 0xEDE6DA, dark: 0x1F1D18)
    public static let line = Color(light: 0xD9D0C1, dark: 0x2E2B24)
    public static let ink = Color(light: 0x141310, dark: 0xF6F1E9)
    public static let ink2 = Color(light: 0x5C574D, dark: 0xA39D90)
    /// iCloud channel: Apple already syncs it.
    public static let moss = Color(light: 0x2E5E4E, dark: 0x7FB39E)
    /// Carry app channel; also the one accent.
    public static let tangerine = Color(light: 0xE8562B, dark: 0xFF7A4D)
    public static let ok = moss
    public static let warn = Color(light: 0xB8860B, dark: 0xE0B54A)
    /// Text on a tangerine fill.
    public static let onAccent = Color(light: 0xF6F1E9, dark: 0x141310)

    public static func color(for channel: Channel) -> Color { channel == .icloud ? moss : tangerine }
}

/// The same tokens for UIKit appearance proxies (tab bar, hosting views).
public enum UITheme {
    public static let paper = UIColor(light: 0xF6F1E9, dark: 0x141310)
    public static let line = UIColor(light: 0xD9D0C1, dark: 0x2E2B24)
    public static let ink = UIColor(light: 0x141310, dark: 0xF6F1E9)
    public static let ink2 = UIColor(light: 0x5C574D, dark: 0xA39D90)
    public static let tangerine = UIColor(light: 0xE8562B, dark: 0xFF7A4D)
}

public extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor(light: light, dark: dark))
    }
}

public extension UIColor {
    convenience init(light: UInt32, dark: UInt32) {
        self.init { traits in UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light) }
    }

    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}

// MARK: - Type

public extension Font {
    /// Screen titles: system serif (New York), sentence case.
    static let screenTitle = Font.system(.largeTitle, design: .serif)
    /// One-sentence statements (welcome, Pro).
    static let lede = Font.system(.title2, design: .serif)
    static let sectionHead = Font.system(.title3, design: .serif)
    /// Paths, commands, timestamps, status lines.
    static let mono = Font.system(.footnote, design: .monospaced)
    static let monoSmall = Font.system(.caption2, design: .monospaced)
}

// MARK: - Page

/// DEBUG hook set from a launch argument: scroll every Screen to its end on appear, so the lower
/// half of a screen can be screenshotted without touching it.
public enum ScreenDebug {
    public static var scrollToBottom = false
}

/// A page: serif title, optional one-line subtitle, then content, on paper.
public struct Screen<Content: View>: View {
    let title: String
    let subtitle: String?
    let content: Content

    public init(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title)
                            .font(.screenTitle)
                            .foregroundStyle(Theme.ink)
                        if let subtitle {
                            Text(subtitle)
                                .font(.body)
                                .foregroundStyle(Theme.ink2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.top, 12)
                    content
                    Color.clear.frame(height: 1).id("carry.screen.bottom")
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onAppear {
                guard ScreenDebug.scrollToBottom else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    proxy.scrollTo("carry.screen.bottom", anchor: .bottom)
                }
            }
        }
        .background(Theme.paper.ignoresSafeArea())
        // Keep the status-bar band opaque while content scrolls under it.
        .overlay(alignment: .top) {
            GeometryReader { geometry in
                Theme.paper
                    .frame(height: geometry.safeAreaInsets.top)
                    .offset(y: -geometry.safeAreaInsets.top)
            }
            .allowsHitTesting(false)
        }
        .toolbarBackground(Theme.paper, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}

/// A titled block: serif section head, content, optional footnote. (Named to avoid SwiftUI.Section.)
public struct Titled<Content: View>: View {
    let title: String
    let note: String?
    let content: Content

    public init(_ title: String, note: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.note = note
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.sectionHead).foregroundStyle(Theme.ink)
            content
            if let note {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 2)
            }
        }
    }
}

// MARK: - Surfaces

/// Hairline card on paper2, 12pt corners, no shadow.
public struct Card<Content: View>: View {
    let padding: CGFloat
    let content: Content

    public init(padding: CGFloat = 14, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.paper2)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line, lineWidth: 1))
    }
}

public struct Hairline: View {
    let inset: CGFloat
    public init(inset: CGFloat = 0) { self.inset = inset }
    public var body: some View {
        Rectangle().fill(Theme.line).frame(height: 1).padding(.leading, inset)
    }
}

/// A row inside a card: title, a mono detail line, an optional trailing view. Rows stack with hairlines.
public struct Row<Trailing: View>: View {
    let title: String
    let detail: String?
    let detailColor: Color
    let trailing: Trailing

    public init(_ title: String, detail: String? = nil, detailColor: Color = Theme.ink2,
                @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.detail = detail
        self.detailColor = detailColor
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.body.weight(.medium)).foregroundStyle(Theme.ink)
                if let detail {
                    Text(detail).font(.mono).foregroundStyle(detailColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

public extension Row where Trailing == EmptyView {
    init(_ title: String, detail: String? = nil, detailColor: Color = Theme.ink2) {
        self.init(title, detail: detail, detailColor: detailColor) { EmptyView() }
    }
}

/// A row that opens a link: title, chevron-less "↗", mono detail.
public struct LinkRow: View {
    let title: String
    let detail: String?
    let action: () -> Void

    public init(_ title: String, detail: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.detail = detail
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Row(title, detail: detail) {
                Image(systemName: "arrow.up.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.ink2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Small pieces

/// `via iCloud` (moss) or `via Carry app` (tangerine).
public struct ChannelBadge: View {
    let channel: Channel
    public init(_ channel: Channel) { self.channel = channel }
    public var body: some View {
        Text(channel.badge)
            .font(.monoSmall)
            .foregroundStyle(Theme.color(for: channel))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.color(for: channel).opacity(0.5), lineWidth: 1))
    }
}

/// Mono status line, e.g. `Mac read 12 min ago · 40 photos · 2 notes · Pro`.
public struct StatusLine: View {
    let text: String
    let color: Color
    public init(_ text: String, color: Color = Theme.ink) {
        self.text = text
        self.color = color
    }
    public var body: some View {
        Text(text)
            .font(.mono)
            .foregroundStyle(color)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A command or path the user may copy, in a mono block.
public struct CodeLine: View {
    let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View {
        Text(text)
            .font(.mono)
            .foregroundStyle(Theme.ink)
            .textSelection(.enabled)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.paper)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Theme.line, lineWidth: 1))
    }
}

/// A footnote with a colored dot: the honest limits (warn) or a reassurance (ok).
public struct Note: View {
    let text: String
    let color: Color
    public init(_ text: String, color: Color = Theme.warn) {
        self.text = text
        self.color = color
    }
    public var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(color).frame(width: 6, height: 6).padding(.top, 7)
            Text(text).font(.footnote).foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A checklist line: a small moss check and body text.
public struct CheckLine: View {
    let text: String
    let color: Color
    public init(_ text: String, color: Color = Theme.ok) {
        self.text = text
        self.color = color
    }
    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "checkmark").font(.footnote.weight(.semibold)).foregroundStyle(color)
            Text(text).font(.body).foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A selectable chip (health sub-types). On = channel color, off = faded.
public struct Chip: View {
    let text: String
    let isOn: Bool
    let color: Color
    let action: () -> Void

    public init(_ text: String, isOn: Bool, color: Color, action: @escaping () -> Void) {
        self.text = text
        self.isOn = isOn
        self.color = color
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: isOn ? "checkmark" : "plus")
                    .font(.caption2.weight(.bold))
                Text(text).font(.subheadline)
            }
            .foregroundStyle(isOn ? color : Theme.ink2)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isOn ? color.opacity(0.08) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isOn ? color.opacity(0.55) : Theme.line, lineWidth: 1))
            .opacity(isOn ? 1 : 0.7)
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: isOn)
    }
}

/// Lays chips out in wrapping rows.
public struct FlowLayout: Layout {
    let spacing: CGFloat
    public init(spacing: CGFloat = 8) { self.spacing = spacing }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width == .infinity ? maxX : width, height: y + rowHeight)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Buttons

/// Filled tangerine button, the one accent.
public struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(Theme.onAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.tangerine.opacity(configuration.isPressed ? 0.8 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(isEnabled ? 1 : 0.55)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Hairline-outlined secondary button.
public struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let tint: Color
    /// `tint` colors the label; use `Theme.tangerine` for a destructive action.
    public init(tint: Color = Theme.ink) { self.tint = tint }
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(configuration.isPressed ? Theme.paper2 : Theme.paper)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line, lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.55)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Text-only button in ink2 (Restore purchases, Not now).
public struct QuietButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline)
            .foregroundStyle(Theme.ink2.opacity(configuration.isPressed ? 0.6 : 1))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
    }
}

// MARK: - Time

public enum TimeText {
    private static let hhmm: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let dayMonth: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMM d")
        return f
    }()

    /// `21:30`
    public static func time(_ date: Date) -> String { hhmm.string(from: date) }
    /// `Oct 7`
    public static func day(_ date: Date) -> String { dayMonth.string(from: date) }
}

public func plural(_ n: Int, _ noun: String, _ plural: String? = nil) -> String {
    "\(n) \(n == 1 ? noun : (plural ?? noun + "s"))"
}

/// Joins status parts with ` · `. Short parts get non-breaking spaces so a line wraps between
/// parts ("40 photos · 2 notes"), never inside one ("2\nnotes").
public func statusJoin(_ parts: [String]) -> String {
    parts.map { $0.count <= 24 ? $0.replacingOccurrences(of: " ", with: "\u{00A0}") : $0 }
        .joined(separator: " · ")
}
