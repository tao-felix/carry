import AppKit
import Foundation

/// `~/.carry` (or `$CARRY_HOME`), the CLI's home. The app writes only `app.json` and `logs/app.log` there.
enum CarryHome {
    static let dir: URL = {
        if let custom = ProcessInfo.processInfo.environment["CARRY_HOME"], !custom.isEmpty {
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".carry", isDirectory: true)
    }()
    static let appJSON = dir.appendingPathComponent("app.json")
    static let logs = dir.appendingPathComponent("logs", isDirectory: true)
    static let context = dir.appendingPathComponent("context", isDirectory: true)

    /// `~/.carry`, for display.
    static var display: String {
        dir.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}

/// `~/.carry/app.json`: "Carry for Mac is running, pid N". The CLI reads it to skip installing its LaunchAgent
/// and treats it as stale after 3 minutes, so the app rewrites it every minute and removes it on quit.
enum Presence {
    static func write(version: String) {
        let info: [String: Any] = [
            "pid": Int(ProcessInfo.processInfo.processIdentifier),
            "version": version,
            "last_seen": RFC3339.string(),
        ]
        try? FileManager.default.createDirectory(at: CarryHome.dir, withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: info, options: [.sortedKeys]) {
            try? data.write(to: CarryHome.appJSON, options: .atomic)
        }
    }

    static func remove() {
        try? FileManager.default.removeItem(at: CarryHome.appJSON)
    }
}

/// Appends timestamped lines to `~/.carry/logs/app.log`.
enum AppLog {
    static let url = CarryHome.logs.appendingPathComponent("app.log")

    static func write(_ message: String, detail: [String] = []) {
        var text = "\(RFC3339.string()) \(message)\n"
        for line in detail { text += "  \(line)\n" }
        let fm = FileManager.default
        try? fm.createDirectory(at: CarryHome.logs, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(text.utf8))
    }
}

/// Full Disk Access: the one switch only the user can flip, in System Settings.
/// Detection is a real read attempt, which is also what makes macOS list "Carry" in the pane.
enum FullDiskAccess {
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
    static let covers = "Messages, Notes, Voice Memos, Calendar, Reminders, Safari, Screen Time"

    private enum Probe { case granted, denied, missing }

    private static func probe(_ path: String) -> Probe {
        let fd = open(path, O_RDONLY)
        if fd >= 0 {
            close(fd)
            return .granted
        }
        return errno == ENOENT ? .missing : .denied
    }

    /// True when this process can read Messages' chat.db; if that file does not exist, Safari's History.db;
    /// if neither exists there is nothing to protect and the answer is true.
    static func check() -> Bool {
        let home = NSHomeDirectory()
        switch probe("\(home)/Library/Messages/chat.db") {
        case .granted: return true
        case .denied: return false
        case .missing:
            return probe("\(home)/Library/Safari/History.db") != .denied
        }
    }
}

/// The CLI's heartbeat to the phone, `heartbeat/<mac-host>.json` in the iCloud container.
enum HeartbeatFile {
    static let dir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Mobile Documents/iCloud~app~carry~ios/Documents/heartbeat", isDirectory: true)

    /// Same rule as the CLI: `socket.gethostname()` before the first dot.
    static var hostName: String {
        var buffer = [CChar](repeating: 0, count: 256)
        gethostname(&buffer, buffer.count - 1)
        let full = String(cString: buffer)
        return full.split(separator: ".").first.map(String.init) ?? full
    }

    /// This Mac's heartbeat, else the most recently written one (host name changed), else nil.
    static func load() -> Heartbeat? {
        let fm = FileManager.default
        let mine = dir.appendingPathComponent("\(hostName).json")
        if let data = try? Data(contentsOf: mine), let hb = try? JSONDecoder.carry.decode(Heartbeat.self, from: data) {
            return hb
        }
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return nil
        }
        let newest = files.filter { $0.pathExtension == "json" }.sorted { a, b in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return da > db
        }.first
        guard let newest, let data = try? Data(contentsOf: newest) else { return nil }
        return try? JSONDecoder.carry.decode(Heartbeat.self, from: data)
    }
}

/// The CLI's own scheduler, `~/Library/LaunchAgents/app.carry.sync.plist`. The app replaces it.
enum LaunchAgent {
    static let plist = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents/app.carry.sync.plist")

    static var isInstalled: Bool { FileManager.default.fileExists(atPath: plist.path) }

    /// `carry init` copies a `CARRY_PRO=1` developer override into the agent; keep it when taking over.
    static var carriesProOverride: Bool {
        guard let data = try? Data(contentsOf: plist),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let env = dict["EnvironmentVariables"] as? [String: Any] else { return false }
        return env["CARRY_PRO"] as? String == "1"
    }
}

/// Every link the app quotes.
enum Links {
    static let site = URL(string: "https://carry-site.vercel.app")!
    static let iosApp = URL(string: "https://carry-site.vercel.app/#ios")!
    static let pro = URL(string: "https://carry-site.vercel.app/#pro")!
    static let source = URL(string: "https://github.com/tao-felix/carry")!
    static let siteLabel = "carry-site.vercel.app"
}
