import Foundation

/// Paths of the CLI's home (`~/.carry`, or `$CARRY_HOME` in DEBUG builds for testing).
enum CarryPaths {
    static var home: URL { CarryHome.dir }
    static var context: URL { home.appendingPathComponent("context", isDirectory: true) }
    static var db: URL { home.appendingPathComponent("carry.db") }
    static var config: URL { home.appendingPathComponent("config.toml") }
    static var logs: URL { home.appendingPathComponent("logs", isDirectory: true) }
    static var tmp: URL { home.appendingPathComponent("tmp", isDirectory: true) }

    static let containerID = "iCloud.app.carry.ios"

    /// `~/Library/Mobile Documents/iCloud~app~carry~ios/Documents`, or `$CARRY_CONTAINER` in DEBUG builds.
    static let container: URL = {
        #if DEBUG
        if let custom = ProcessInfo.processInfo.environment["CARRY_CONTAINER"], !custom.isEmpty {
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath, isDirectory: true)
        }
        #endif
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/iCloud~app~carry~ios/Documents", isDirectory: true)
    }()

    static let proProductID = "app.carry.pro"
    static let proProductIDs: Set<String> = ["app.carry.pro", "app.carry.pro.annual"]
}

/// The source registry of config.py: name, channel, label, what is read, default.
struct Source {
    let name: String
    let channel: Channel
    let label: String
    let reads: String
    let defaultOn: Bool
}

enum Sources {
    static let all: [Source] = [
        Source(name: "photos", channel: .icloud, label: "Photos", reads: "New photos: time, place, caption. Text inside them with Pro.", defaultOn: true),
        Source(name: "screenshots", channel: .icloud, label: "Screenshots", reads: "New screenshots. The text inside them with Pro.", defaultOn: true),
        Source(name: "voice_memos", channel: .icloud, label: "Voice Memos", reads: "New recordings: title, length. Transcript with Pro.", defaultOn: true),
        Source(name: "notes", channel: .icloud, label: "Notes", reads: "Notes edited today: title and text.", defaultOn: true),
        Source(name: "messages", channel: .icloud, label: "Messages", reads: "iMessage and SMS threads active today.", defaultOn: false),
        Source(name: "calendar", channel: .icloud, label: "Calendar", reads: "Today's and upcoming events.", defaultOn: true),
        Source(name: "reminders", channel: .icloud, label: "Reminders", reads: "Due, overdue and completed today.", defaultOn: true),
        Source(name: "safari", channel: .icloud, label: "Safari", reads: "Pages visited today.", defaultOn: false),
        Source(name: "screen_time", channel: .icloud, label: "Screen Time", reads: "Apps used today and for how long.", defaultOn: true),
        Source(name: "health", channel: .app, label: "Health", reads: "Sleep, steps, heart rate, HRV, workouts, weight, blood oxygen.", defaultOn: true),
        Source(name: "location", channel: .app, label: "Location", reads: "Places visited: arrive, leave, where.", defaultOn: true),
        Source(name: "inbox", channel: .app, label: "Share inbox", reads: "Anything you shared to Carry from any app.", defaultOn: true),
    ]

    static let names: [String] = all.map(\.name)

    static func by(_ name: String) -> Source? { all.first { $0.name == name } }

    static func label(_ name: String) -> String { by(name)?.label ?? name }
}

/// `sources.json` from the phone, `config.toml` on the Mac: the phone wins.
enum Config {
    /// DEFAULT_CONFIG, as an ordered JSON object so the TOML we write has the CLI's layout.
    static var defaults: JSON {
        .object([
            ("carry", .object([("backfill_days", .int(30)), ("schedule_minutes", .int(15))])),
            ("sources", .object(Sources.all.map { ($0.name, .bool($0.defaultOn)) })),
            ("processing", .object([
                ("ocr", .bool(true)), ("transcribe", .bool(true)), ("ocr_photos", .bool(false)),
                ("transcribe_max_minutes", .int(90)), ("max_transcriptions_per_run", .int(3)),
                ("whisper_model", .string("mlx-community/whisper-large-v3-turbo")),
            ])),
        ])
    }

    /// `load_config()`: defaults updated section by section from config.toml.
    static func load() -> JSON {
        var cfg = defaults
        guard let text = try? String(contentsOf: CarryPaths.config, encoding: .utf8), let user = TOML.parse(text) else { return cfg }
        for (section, values) in user.pairs ?? [] {
            var merged = cfg[section] ?? .object([])
            if case .object = merged { merged.update(values) } else { merged = values }
            cfg.set(section, merged)
        }
        return cfg
    }

    /// `save_config(cfg)`: the CLI's simple TOML layout, so both agree.
    static func save(_ cfg: JSON) throws {
        try FileManager.default.createDirectory(at: CarryPaths.home, withIntermediateDirectories: true)
        try TOML.dump(cfg).write(to: CarryPaths.config, atomically: true, encoding: .utf8)
    }

    /// `phone_policy()`
    static func phonePolicy() -> JSON? {
        let p = CarryPaths.container.appendingPathComponent("sources.json")
        guard let data = try? Data(contentsOf: p) else { return nil }
        return JSON.parse(data)
    }

    /// `effective_sources(cfg)`: which sources are on, and who decided ("phone" or "mac").
    static func effectiveSources(_ cfg: JSON) -> (enabled: [String: Bool], decidedBy: String) {
        var enabled: [String: Bool] = [:]
        if let policy = phonePolicy(), let sources = policy["sources"], case .object = sources {
            for s in Sources.all {
                if let entry = sources[s.name], case .object = entry {
                    enabled[s.name] = (entry["enabled"] ?? .bool(s.defaultOn)).truthy
                } else {
                    enabled[s.name] = (cfg["sources"]?[s.name] ?? .bool(s.defaultOn)).truthy
                }
            }
            return (enabled, "phone")
        }
        for s in Sources.all {
            enabled[s.name] = (cfg["sources"]?[s.name] ?? .bool(s.defaultOn)).truthy
        }
        return (enabled, "mac")
    }

    /// `effective_processing(cfg)`
    static func effectiveProcessing(_ cfg: JSON) -> JSON {
        var proc = cfg["processing"] ?? .object([])
        if let policy = phonePolicy(), let p = policy["processing"], case .object = p {
            for k in ["ocr", "transcribe"] {
                if let v = p[k] { proc.set(k, .bool(v.truthy)) }
            }
        }
        return proc
    }

    /// `policy_updated_at()`
    static func policyUpdatedAt() -> String? {
        guard let policy = phonePolicy() else { return nil }
        return PyTime.iso(PyTime.parseISO(policy["updated_at"]?.string))
    }

    static func backfillDays(_ cfg: JSON) -> Int { Int(cfg["carry"]?["backfill_days"]?.int ?? 30) }
}

/// The subset of TOML the CLI writes (`[section]` / `key = value` with bools, numbers and basic strings).
enum TOML {
    static func parse(_ text: String) -> JSON? {
        var sections: [(String, JSON)] = []
        var current: String? = nil
        for rawLine in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            var line = String(rawLine)
            if let hash = line.firstIndex(of: "#"), !line[..<hash].contains("\"") { line = String(line[..<hash]) }
            line = line.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("[") && line.hasSuffix("]") {
                let name = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                current = name
                if !sections.contains(where: { $0.0 == name }) { sections.append((name, .object([]))) }
                continue
            }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let raw = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            guard let value = parseValue(raw) else { continue }
            let section = current ?? ""
            if let i = sections.firstIndex(where: { $0.0 == section }) {
                sections[i].1.set(key, value)
            } else {
                sections.append((section, .object([(key, value)])))
            }
        }
        return .object(sections)
    }

    private static func parseValue(_ raw: String) -> JSON? {
        if raw == "true" { return .bool(true) }
        if raw == "false" { return .bool(false) }
        if raw.hasPrefix("\"") {
            var s = String(raw.dropFirst())
            if let end = s.firstIndex(of: "\"") { s = String(s[..<end]) }
            return .string(s.replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\"))
        }
        if raw.hasPrefix("'") {
            var s = String(raw.dropFirst())
            if let end = s.firstIndex(of: "'") { s = String(s[..<end]) }
            return .string(s)
        }
        if let i = Int64(raw) { return .int(i) }
        if let d = Double(raw) { return .double(d) }
        return nil
    }

    /// `_toml_dump(d)`
    static func dump(_ cfg: JSON) -> String {
        var lines: [String] = []
        for (section, values) in cfg.pairs ?? [] {
            lines.append("[\(section)]")
            for (k, v) in values.pairs ?? [] {
                switch v {
                case .bool(let b): lines.append("\(k) = \(b ? "true" : "false")")
                case .int(let i): lines.append("\(k) = \(i)")
                case .double(let d): lines.append("\(k) = \(Py.repr(d))")
                default: lines.append("\(k) = \"\(v.pyStr)\"")
                }
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}
