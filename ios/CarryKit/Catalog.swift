import Foundation

/// How a source reaches the Mac. Two channels, two colors (DESIGN.md).
public enum Channel: String, Codable, Sendable {
    case icloud
    case app

    public var badge: String { self == .icloud ? "via iCloud" : "via Carry app" }
}

/// Every source the engine knows about (DATA-CONTRACT.md §3), with the copy shown in the app.
public enum SourceID: String, CaseIterable, Identifiable, Sendable {
    case photos, screenshots
    case voiceMemos = "voice_memos"
    case notes, messages, calendar, reminders, safari
    case screenTime = "screen_time"
    case health, location, inbox

    public var id: String { rawValue }

    public var channel: Channel {
        switch self {
        case .health, .location, .inbox: return .app
        default: return .icloud
        }
    }

    /// Defaults on first install: everything on except messages and safari.
    public var defaultEnabled: Bool { self != .messages && self != .safari }

    public static var icloudSources: [SourceID] { allCases.filter { $0.channel == .icloud } }
    public static var appSources: [SourceID] { allCases.filter { $0.channel == .app } }

    public var title: String {
        switch self {
        case .photos: return "Photos"
        case .screenshots: return "Screenshots"
        case .voiceMemos: return "Voice Memos"
        case .notes: return "Notes"
        case .messages: return "Messages"
        case .calendar: return "Calendar"
        case .reminders: return "Reminders"
        case .safari: return "Safari"
        case .screenTime: return "Screen Time"
        case .health: return "Health"
        case .location: return "Location"
        case .inbox: return "Inbox"
        }
    }

    /// One line saying exactly what is read. Kept identical to cli/src/carry/config.py.
    public var reads: String {
        switch self {
        case .photos: return "New photos: time, place, caption. Text inside them with Pro."
        case .screenshots: return "New screenshots. The text inside them with Pro."
        case .voiceMemos: return "New recordings: title, length. Transcript with Pro."
        case .notes: return "Notes edited today: title and text."
        case .messages: return "iMessage and SMS threads active today."
        case .calendar: return "Today's and upcoming events."
        case .reminders: return "Due, overdue and completed today."
        case .safari: return "Pages visited today."
        case .screenTime: return "Apps used today and for how long."
        case .health: return "Only the types below: sleep, steps, heart rate, HRV, workouts, weight, blood oxygen."
        case .location: return "Places visited: arrive, leave, where."
        case .inbox: return "Anything you shared to Carry from any app."
        }
    }
}

/// The nine health types (DATA-CONTRACT.md §3 / §4).
public enum HealthType: String, CaseIterable, Identifiable, Sendable {
    case sleep, steps
    case heartRate = "heart_rate"
    case restingHeartRate = "resting_heart_rate"
    case hrv
    case activeEnergy = "active_energy"
    case workouts
    case bodyMass = "body_mass"
    case bloodOxygen = "blood_oxygen"

    public var id: String { rawValue }

    /// The `t` value written to health JSONL (`workouts` → `workout`).
    public var recordType: String { self == .workouts ? "workout" : rawValue }

    public var title: String {
        switch self {
        case .sleep: return "Sleep"
        case .steps: return "Steps"
        case .heartRate: return "Heart rate"
        case .restingHeartRate: return "Resting heart rate"
        case .hrv: return "Heart rate variability"
        case .activeEnergy: return "Active energy"
        case .workouts: return "Workouts"
        case .bodyMass: return "Body mass"
        case .bloodOxygen: return "Blood oxygen"
        }
    }
}
