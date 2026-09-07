import Foundation

// The shapes `carry status --json` and `carry sources --json` emit (cli/src/carry/cli.py).
// Every field is optional so an older or newer CLI degrades to "unknown", never to a crash.

/// How a source reaches the Mac. Two channels, two colors (docs/DESIGN.md).
enum Channel: String, Decodable {
    case icloud
    case app

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Channel(rawValue: raw) ?? .icloud
    }

    var badge: String { self == .icloud ? "via iCloud" : "via Carry app" }
}

struct SourceRow: Decodable, Identifiable {
    let name: String
    let label: String
    let channel: Channel
    var enabled: Bool
    let items: Int?
    let lastRun: String?
    let error: String?

    var id: String { name }
}

struct ProStatus: Decodable {
    let active: Bool
    let reason: String?
    let expiresAt: String?
}

struct PhoneInfo: Decodable {
    let name: String?
    let os: String?
    let appVersion: String?
    let updatedAt: String?
}

struct CarryStatus: Decodable {
    let version: String?
    let home: String?
    let contextDir: String?
    let decidedBy: String?
    let pro: ProStatus?
    let fda: Bool?
    var agentInstalled: Bool?
    let appRunning: Bool?
    let lastSyncAt: String?
    let sources: [SourceRow]?
    let phone: PhoneInfo?
    let pending: [String: Int]?
    let blocked: [String]?

    /// Pictures and recordings waiting for Pro to become text.
    var pendingTotal: Int { pending?.values.reduce(0, +) ?? 0 }
}

/// `heartbeat/<mac-host>.json`, written by the CLI for the phone (docs/DATA-CONTRACT.md §8).
struct Heartbeat: Decodable {
    let host: String
    let carryVersion: String?
    let lastSyncAt: String?
}

extension JSONDecoder {
    /// snake_case JSON from the CLI into the camelCase fields above.
    static let carry: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()
}

/// RFC 3339 with offset, the one timestamp format of the data contract.
enum RFC3339 {
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = .current
        return f
    }()

    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = .current
        return f
    }()

    /// `2026-09-07T21:30:00+08:00`
    static func string(_ date: Date = Date()) -> String { plain.string(from: date) }

    static func parse(_ text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        return plain.date(from: text) ?? fractional.date(from: text)
    }
}
