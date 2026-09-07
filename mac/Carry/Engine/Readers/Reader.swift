import Foundation

/// Readers for data Apple already synced to this Mac (cli/src/carry/sources/). Each answers
/// `available()` → (ok, note) and `collect(...)` → number of new items. Read-only, never copied.
protocol Reader {
    static func available() -> (Bool, String)
    static func collect(store: Store, cfg: JSON, backfillStart: Date, enabled: [String: Bool]) throws -> Int
}

enum Readers {
    /// One reader, two switches for photos and screenshots; `Photos.collect` honours both.
    static func reader(for source: String) -> Reader.Type? {
        switch source {
        case "photos", "screenshots": return PhotosReader.self
        case "voice_memos": return VoiceMemosReader.self
        case "notes": return NotesReader.self
        case "messages": return MessagesReader.self
        case "calendar": return CalendarReader.self
        case "reminders": return RemindersReader.self
        case "safari": return SafariReader.self
        case "screen_time": return ScreenTimeReader.self
        default: return nil
        }
    }

    static let home = FileManager.default.homeDirectoryForCurrentUser

    /// Files matching `dir/<prefix>*<suffix>` sorted like Python's `sorted(glob(...))` (code point order).
    static func glob(_ dir: URL, prefix: String = "", suffix: String = "") -> [URL] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [] }
        return names.filter { $0.hasPrefix(prefix) && $0.hasSuffix(suffix) && $0.count >= prefix.count + suffix.count }
            .sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
            .map { dir.appendingPathComponent($0) }
    }

    /// `f"{n:,} things"`
    static func countNote(_ value: SQLValue, _ noun: String) -> String {
        "\(Py.thousands(Int(value.int ?? 0))) \(noun)"
    }
}
