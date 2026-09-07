import AppKit
import SwiftUI

// The component vocabulary of ios/CarryKit/UI.swift, written for macOS.

// MARK: - Sections and surfaces

/// A titled block: serif section head, content, optional footnote.
struct Titled<Content: View>: View {
    let title: String
    let note: String?
    let content: Content

    init(_ title: String, note: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.note = note
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.sectionHead).foregroundStyle(Theme.ink)
            content
            if let note {
                Text(note)
                    .font(.small)
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 2)
            }
        }
    }
}

/// Hairline card on paper2, 12pt corners, no shadow.
struct Card<Content: View>: View {
    let padding: CGFloat
    let content: Content

    init(padding: CGFloat = 14, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.paper2)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line, lineWidth: 1))
    }
}

struct Hairline: View {
    let inset: CGFloat
    init(inset: CGFloat = 0) { self.inset = inset }
    var body: some View {
        Rectangle().fill(Theme.line).frame(height: 1).padding(.leading, inset)
    }
}

// MARK: - Small pieces

/// `via iCloud` (moss) or `via Carry app` (tangerine).
struct ChannelBadge: View {
    let channel: Channel
    init(_ channel: Channel) { self.channel = channel }
    var body: some View {
        Text(channel.badge)
            .font(.monoSmall)
            .foregroundStyle(Theme.color(for: channel))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.color(for: channel).opacity(0.5), lineWidth: 1))
    }
}

/// Mono status line, e.g. `Last sync 00:42 · photos 252 · Pro`.
struct StatusLine: View {
    let text: String
    let color: Color
    init(_ text: String, color: Color = Theme.ink) {
        self.text = text
        self.color = color
    }
    var body: some View {
        Text(text)
            .font(.mono)
            .foregroundStyle(color)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A command or path the user may copy, in a mono block, with a Copy button.
struct CodeLine: View {
    let text: String
    @State private var copied = false

    init(_ text: String) { self.text = text }

    var body: some View {
        HStack(spacing: 10) {
            Text(text)
                .font(.mono)
                .foregroundStyle(Theme.ink)
                .textSelection(.enabled)
            Spacer(minLength: 8)
            Button(copied ? "Copied" : "Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
            }
            .buttonStyle(QuietButtonStyle())
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .background(Theme.paper)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Theme.line, lineWidth: 1))
    }
}

/// A multi-line block the user may copy (a paragraph, a TOML snippet), mono, with a Copy button at the top right.
struct CodeBlock: View {
    let text: String
    @State private var copied = false

    init(_ text: String) { self.text = text }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(text)
                .font(.mono)
                .foregroundStyle(Theme.ink)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button(copied ? "Copied" : "Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
            }
            .buttonStyle(QuietButtonStyle())
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .padding(.vertical, 6)
        .background(Theme.paper)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Theme.line, lineWidth: 1))
    }
}

/// A footnote with a colored dot: the honest limits (warn) or a reassurance (ok).
struct Note: View {
    let text: String
    let color: Color
    init(_ text: String, color: Color = Theme.warn) {
        self.text = text
        self.color = color
    }
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(color).frame(width: 6, height: 6).padding(.top, 5)
            Text(text).font(.small).foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A checklist line: a small moss check and body text.
struct CheckLine: View {
    let text: String
    let color: Color
    init(_ text: String, color: Color = Theme.ok) {
        self.text = text
        self.color = color
    }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(color)
            Text(text).font(.bodyText).foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A text link that opens in the browser: label, "↗", hand cursor. Ink2, never blue.
struct LinkText: View {
    let title: String
    let url: URL
    let color: Color

    init(_ title: String, url: URL, color: Color = Theme.ink2) {
        self.title = title
        self.url = url
        self.color = color
    }

    var body: some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            HStack(spacing: 3) {
                Text(title).font(.small)
                Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(color)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHand()
    }
}

/// A selectable chip (schedule minutes). On = ink on paper2; off = ink2 with the line hairline.
struct Chip: View {
    let text: String
    let isOn: Bool
    let action: () -> Void

    init(_ text: String, isOn: Bool, action: @escaping () -> Void) {
        self.text = text
        self.isOn = isOn
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.small)
                .foregroundStyle(isOn ? Theme.ink : Theme.ink2)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(isOn ? Theme.paper2 : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isOn ? Theme.ink2.opacity(0.6) : Theme.line, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: isOn)
    }
}

// MARK: - Toggle

/// A small pill switch in the channel color (moss / tangerine). Native NSSwitch would use the system accent.
struct PillToggleStyle: ToggleStyle {
    let color: Color
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 8) {
                configuration.label
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(configuration.isOn ? color : Theme.line)
                        .frame(width: 30, height: 17)
                    Circle()
                        .fill(Theme.paper)
                        .frame(width: 13, height: 13)
                        .padding(2)
                }
                .overlay(Capsule().stroke(configuration.isOn ? color : Theme.ink2.opacity(0.35), lineWidth: 1))
                .animation(.easeOut(duration: 0.15), value: configuration.isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.55)
    }
}

// MARK: - Buttons

/// Filled tangerine button, the one accent.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.bodyMedium)
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Theme.tangerine.opacity(configuration.isPressed ? 0.8 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(isEnabled ? 1 : 0.55)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Hairline-outlined secondary button.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.bodyMedium)
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(configuration.isPressed ? Theme.paper2 : Theme.paper)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Theme.line, lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.55)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Text-only button in ink2 (Copy, Not now).
struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.small)
            .foregroundStyle(Theme.ink2.opacity(configuration.isPressed ? 0.6 : 1))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
    }
}

extension View {
    /// Hand cursor on hover, for text links.
    func pointingHand() -> some View {
        onHover { inside in
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

// MARK: - Time and text helpers

enum TimeText {
    private static let hhmm: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let dayTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d HH:mm"
        return f
    }()

    /// `21:30` today, `Sep 7 21:30` on another day.
    static func short(_ date: Date) -> String {
        Calendar.current.isDateInToday(date) ? hhmm.string(from: date) : dayTime.string(from: date)
    }
}

func plural(_ n: Int, _ noun: String, _ plural: String? = nil) -> String {
    "\(n) \(n == 1 ? noun : (plural ?? noun + "s"))"
}

/// Joins status parts with ` · `. Short parts get non-breaking spaces so a line wraps between
/// parts ("40 photos · 2 notes"), never inside one ("2\nnotes").
func statusJoin(_ parts: [String]) -> String {
    parts.map { $0.count <= 24 ? $0.replacingOccurrences(of: " ", with: "\u{00A0}") : $0 }
        .joined(separator: " · ")
}
