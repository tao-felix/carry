import AppKit
import Foundation

/// `~/.carry`, the home the engine shares with the CLI. DEBUG builds honour `$CARRY_HOME` for testing.
enum CarryHome {
    static let dir: URL = {
        #if DEBUG
        if let custom = ProcessInfo.processInfo.environment["CARRY_HOME"], !custom.isEmpty {
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath, isDirectory: true)
        }
        #endif
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".carry", isDirectory: true)
    }()
    static let appJSON = dir.appendingPathComponent("app.json")
    static let logs = dir.appendingPathComponent("logs", isDirectory: true)
    static let context = dir.appendingPathComponent("context", isDirectory: true)

    /// True when a DEBUG run points at a scratch home; then the app leaves the real LaunchAgent alone.
    static var isScratch: Bool {
        dir.path != FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".carry").path
    }

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
    private static let lock = NSLock()

    static func write(_ message: String, detail: [String] = []) {
        var text = "\(RFC3339.string()) \(message)\n"
        for line in detail { text += "  \(line)\n" }
        lock.lock()
        defer { lock.unlock() }
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

    /// macOS keeps a running process's verdict until it relaunches. A child process (attributed to this app)
    /// gets a fresh one, so this says whether the switch is on even when `check()` still says no.
    static func checkFromChild() -> Bool {
        let home = NSHomeDirectory()
        let target = FileManager.default.fileExists(atPath: "\(home)/Library/Messages/chat.db")
            ? "\(home)/Library/Messages/chat.db" : "\(home)/Library/Safari/History.db"
        guard FileManager.default.fileExists(atPath: target) else { return true }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/dd")
        p.arguments = ["if=\(target)", "of=/dev/null", "bs=1", "count=1"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            p.waitUntilExit()
            return p.terminationStatus == 0
        } catch {
            return false
        }
    }
}

/// The engine's heartbeat to the phone, `heartbeat/<mac-host>.json` in the iCloud container.
enum HeartbeatFile {
    static var dir: URL { CarryPaths.container.appendingPathComponent("heartbeat", isDirectory: true) }

    static var hostName: String { Container.hostName }

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
    static let label = "app.carry.sync"
    static let plist = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents/\(label).plist")

    static var isInstalled: Bool { FileManager.default.fileExists(atPath: plist.path) }

    /// `carry init` copies a `CARRY_PRO=1` developer override into the agent; keep it when taking over.
    static var carriesProOverride: Bool {
        guard let data = try? Data(contentsOf: plist),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let env = dict["EnvironmentVariables"] as? [String: Any] else { return false }
        return env["CARRY_PRO"] as? String == "1"
    }

    /// `carry agent uninstall`: bootout, then remove the plist.
    @discardableResult
    static func uninstall() -> Bool {
        guard isInstalled else { return false }
        _ = Shell.run("/bin/launchctl", ["bootout", "gui/\(getuid())", plist.path], timeout: 20)
        try? FileManager.default.removeItem(at: plist)
        return !isInstalled
    }
}

/// Running a helper the user already has (`claude`), with no shell.
enum Shell {
    struct Outcome {
        let exitCode: Int32
        let output: String
        var ok: Bool { exitCode == 0 }
        /// The last non-empty line.
        var tail: String {
            output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.last { !$0.isEmpty } ?? ""
        }
    }

    static var searchPath: String {
        "\(NSHomeDirectory())/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
    }

    /// `~/.local/bin/<name>`, `/opt/homebrew/bin/<name>`, `/usr/local/bin/<name>`, then PATH.
    static func locate(_ name: String) -> String? {
        var candidates = ["\(NSHomeDirectory())/.local/bin/\(name)", "/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)"]
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        candidates += path.split(separator: ":").map { "\($0)/\(name)" }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 60) -> Outcome {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = searchPath
        environment["HOME"] = NSHomeDirectory()
        process.environment = environment
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return Outcome(exitCode: -1, output: "could not start \(executable): \(error.localizedDescription)")
        }
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        return Outcome(exitCode: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }

    static func runAsync(_ executable: String, _ arguments: [String], timeout: TimeInterval = 60) async -> Outcome {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: run(executable, arguments, timeout: timeout))
            }
        }
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
