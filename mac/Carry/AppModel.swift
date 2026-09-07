import AppKit
import Observation
import ServiceManagement
import SwiftUI

/// What the last sync this app ran came to.
struct SyncOutcome {
    let endedAt: Date
    let ok: Bool
    let summary: String
}

/// All app state and every action. One instance, on the main actor. Views read it; timers and the engine feed it.
@MainActor @Observable
final class AppModel {
    static let shared = AppModel()

    static let appVersion = Engine.version
    static let scheduleChoices = [5, 15, 30, 60]
    private static let scheduleKey = "scheduleMinutes"
    private static let launchedKey = "hasLaunchedBefore"

    // Engine
    private(set) var status: CarryStatus?

    // Sync
    private(set) var isSyncing = false
    private(set) var syncStartedAt: Date?
    private(set) var lastSync: SyncOutcome?
    private var lastSyncStartedAt: Date?
    private var isRefreshing = false
    private var lastStatusRefresh: Date?

    // Full Disk Access
    private(set) var fdaGranted = FullDiskAccess.check()
    private(set) var fdaWaiting = false
    /// The switch is on, but this running process still holds the old verdict.
    private(set) var fdaNeedsRelaunch = false

    // Login item and schedule
    private(set) var loginItemStatus = SMAppService.mainApp.status
    private(set) var loginItemError: String?
    var scheduleMinutes: Int {
        didSet { UserDefaults.standard.set(scheduleMinutes, forKey: Self.scheduleKey) }
    }

    // Phone and sources
    private(set) var heartbeat: Heartbeat?
    private(set) var sourceOverrides: [String: Bool] = [:]
    private(set) var sourceNote: String?

    // For agents
    private(set) var claudePath: String? = Shell.locate("claude")
    private(set) var claudeResult: String?
    private(set) var codexResult: String?
    var codexConfigExists: Bool { FileManager.default.fileExists(atPath: Self.codexConfig.path) }
    var mcpRunning: Bool { MCPServer.shared.isRunning }

    // Bookkeeping
    private var timer: Timer?
    private var lastPresenceWrite: Date?
    private var tookOverScheduling = false
    /// DEBUG: render the "not granted" Full Disk Access card and a sample iPhone for screenshots.
    var previewMode = false
    /// DEBUG: `-carryNoProcess 1` skips OCR / transcription; `-carrySyncAndQuit 1` syncs once and exits.
    var noProcess = false
    var syncAndQuit = false

    private init() {
        let stored = UserDefaults.standard.integer(forKey: Self.scheduleKey)
        scheduleMinutes = Self.scheduleChoices.contains(stored) ? stored : 15
    }

    // MARK: - Lifecycle

    func start() {
        AppLog.write("app \(Self.appVersion) launched, pid \(ProcessInfo.processInfo.processIdentifier), home \(CarryHome.dir.path)")
        writePresence()
        MCPServer.shared.start()
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil,
                                                          queue: .main) { _ in
            Task { @MainActor in self.didWake() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            Task { @MainActor in await self.tick() }
        }
        Task { await boot() }
    }

    func stop() {
        timer?.invalidate()
        MCPServer.shared.stop()
        Presence.remove()
        AppLog.write("app quit")
    }

    /// Open the window on the first launch ever, and whenever something needs the user (no FDA).
    var shouldOpenWindowAtLaunch: Bool {
        let first = !UserDefaults.standard.bool(forKey: Self.launchedKey)
        UserDefaults.standard.set(true, forKey: Self.launchedKey)
        return first || !fdaGranted
    }

    private func boot() async {
        await refreshStatus()
        await sync(reason: "launch")
        if syncAndQuit {
            AppLog.write("sync-and-quit: done")
            NSApp.terminate(nil)
        }
    }

    private func tick() async {
        let now = Date()
        if lastPresenceWrite.map({ now.timeIntervalSince($0) >= 60 }) ?? true { writePresence() }
        if !isSyncing, let started = lastSyncStartedAt, now.timeIntervalSince(started) >= Double(scheduleMinutes * 60) {
            await sync(reason: "every \(scheduleMinutes) min")
            return
        }
        if !isSyncing, lastStatusRefresh.map({ now.timeIntervalSince($0) >= 60 }) ?? true {
            await refreshStatus()
        }
    }

    private func didWake() {
        guard !isSyncing else { return }
        if let started = lastSyncStartedAt, Date().timeIntervalSince(started) < 60 { return }
        Task { await sync(reason: "wake") }
    }

    private func writePresence() {
        Presence.write(version: Self.appVersion)
        lastPresenceWrite = Date()
    }

    // MARK: - Status

    func refreshStatus() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let parsed = await Engine.shared.status()
        lastStatusRefresh = Date()
        if let parsed {
            status = parsed
            sourceOverrides = [:]
            fdaGranted = FullDiskAccess.check()
            heartbeat = HeartbeatFile.load()
            if parsed.agentInstalled == true { takeOverScheduling() }
        } else {
            AppLog.write("status failed: could not open \(CarryPaths.db.path)")
        }
        loginItemStatus = SMAppService.mainApp.status
    }

    /// While this app runs it is the scheduler, and every sync it starts inherits its Full Disk Access.
    /// The CLI's LaunchAgent (bare python, no FDA) would only duplicate the work, so remove it once.
    private func takeOverScheduling() {
        guard !tookOverScheduling, !CarryHome.isScratch else { return }
        tookOverScheduling = true
        if LaunchAgent.carriesProOverride { UserDefaults.standard.set(true, forKey: License.overrideKey) }
        let removed = LaunchAgent.uninstall()
        AppLog.write(removed ? "LaunchAgent removed; Carry for Mac schedules the sync now" : "LaunchAgent not removed")
        if removed { status?.agentInstalled = false }
    }

    // MARK: - Sync

    func sync(reason: String) async {
        guard !isSyncing else { return }
        isSyncing = true
        let started = Date()
        syncStartedAt = started
        lastSyncStartedAt = started
        AppLog.write("sync start (\(reason))\(noProcess ? " [no-process]" : "")")
        var lines: [String] = []
        let result = await Engine.shared.sync(noProcess: noProcess) { line in lines.append(line) }
        isSyncing = false
        switch result {
        case .success(let r):
            let failed = r.errors.map { "\($0.0): \($0.1)" }
            lastSync = SyncOutcome(endedAt: Date(), ok: true, summary: r.summaryLine)
            AppLog.write("sync done in \(String(format: "%.1f", r.duration)) s", detail: lines + failed)
        case .failure(let error):
            lastSync = SyncOutcome(endedAt: Date(), ok: false, summary: "\(error)")
            AppLog.write("sync failed: \(error)", detail: lines)
        }
        await refreshStatus()
    }

    /// The mono line under the title and in the menu.
    var statusLine: (text: String, color: Color) {
        if isSyncing, let started = syncStartedAt {
            return ("Syncing… since \(TimeText.short(started))", Theme.ink)
        }
        if let last = lastSync, !last.ok {
            return ("Sync failed \(TimeText.short(last.endedAt)) · \(last.summary)", Theme.warn)
        }
        guard let status else { return ("Reading status…", Theme.ink2) }
        var parts: [String] = []
        if let at = lastSync?.endedAt ?? RFC3339.parse(status.lastSyncAt) {
            parts.append("Last sync \(TimeText.short(at))")
        } else {
            parts.append("No sync yet")
        }
        let top = (status.sources ?? []).filter { $0.enabled && ($0.items ?? 0) > 0 }
            .sorted { ($0.items ?? 0) > ($1.items ?? 0) }.prefix(3)
        parts += top.map { "\($0.label.lowercased()) \($0.items ?? 0)" }
        if status.pro?.active == true { parts.append("Pro") }
        return (statusJoin(parts), Theme.ink)
    }

    // MARK: - Full Disk Access

    /// (a) a real read attempt, so macOS lists "Carry" in the pane; (b) open the pane; (c) poll until granted.
    func grantFDA() {
        fdaGranted = FullDiskAccess.check()
        if fdaGranted {
            Task { await fdaBecameGranted() }
            return
        }
        NSWorkspace.shared.open(FullDiskAccess.settingsURL)
        guard !fdaWaiting else { return }
        fdaWaiting = true
        AppLog.write("FDA: opened System Settings, waiting for the switch")
        Task { [weak self] in
            for _ in 0 ..< 900 { // up to 30 minutes
                try? await Task.sleep(for: .seconds(2))
                guard let self, self.fdaWaiting else { return }
                if FullDiskAccess.check() {
                    self.fdaWaiting = false
                    self.fdaGranted = true
                    self.fdaNeedsRelaunch = false
                    AppLog.write("FDA granted")
                    await self.fdaBecameGranted()
                    return
                }
                // macOS applies a new grant to processes started afterwards and keeps this process's own
                // verdict until relaunch; a child of this app sees the new state.
                let child = await Task.detached { FullDiskAccess.checkFromChild() }.value
                if child {
                    self.fdaWaiting = false
                    self.fdaNeedsRelaunch = true
                    AppLog.write("FDA granted; this process needs a relaunch to use it")
                    return
                }
            }
            self?.fdaWaiting = false
        }
    }

    func stopWaitingForFDA() {
        fdaWaiting = false
    }

    /// Start a fresh instance (which gets the new Full Disk Access verdict) and quit this one.
    func relaunch() {
        AppLog.write("relaunch requested")
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    private func fdaBecameGranted() async {
        await sync(reason: "full disk access granted")
    }

    /// What the cards show. In DEBUG preview mode the "not granted" state is rendered for screenshots.
    var fdaGrantedForDisplay: Bool { previewMode ? false : fdaGranted }

    // MARK: - Sources

    /// Rows from the last status, with toggles the user just flipped applied until the next refresh.
    var sources: [SourceRow] {
        (status?.sources ?? []).map { row in
            var row = row
            if let override = sourceOverrides[row.name] { row.enabled = override }
            return row
        }
    }

    var decidedOnPhone: Bool { status?.decidedBy == "phone" }

    func setSource(_ name: String, enabled: Bool) {
        guard !decidedOnPhone else { return }
        sourceOverrides[name] = enabled
        Task {
            let note = await Engine.shared.setSource(name, enabled: enabled)
            AppLog.write("sources \(name) \(enabled ? "on" : "off")" + (note.map { " (\($0))" } ?? ""))
            sourceNote = note
            await refreshStatus()
        }
    }

    // MARK: - Phone

    var phoneForDisplay: PhoneInfo? {
        if previewMode {
            return PhoneInfo(name: "Tao's iPhone", os: "iOS 26.0", appVersion: "0.1.0", updatedAt: RFC3339.string())
        }
        return status?.phone
    }

    var heartbeatForDisplay: Heartbeat? {
        if previewMode {
            return Heartbeat(host: HeartbeatFile.hostName, carryVersion: Self.appVersion, lastSyncAt: RFC3339.string())
        }
        return heartbeat
    }

    // MARK: - For agents

    static let claudeAddCommand = "claude mcp add --transport http carry \(MCPServer.url)"
    static let codexBlock = "[mcp_servers.carry]\nurl = \"\(MCPServer.url)\"\ndefault_tools_approval_mode = \"auto\"\n"
    static let codexConfig = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/config.toml")

    /// `claude mcp add --transport http carry http://127.0.0.1:47850/mcp`, when the `claude` binary exists.
    func addToClaudeCode() {
        claudePath = Shell.locate("claude")
        guard let claude = claudePath else { return }
        claudeResult = "Running…"
        Task {
            let outcome = await Shell.runAsync(claude, ["mcp", "add", "--transport", "http", "carry", MCPServer.url], timeout: 60)
            let line = outcome.tail.isEmpty ? (outcome.ok ? "Added." : "exit \(outcome.exitCode)") : outcome.tail
            claudeResult = line
            AppLog.write("claude mcp add → exit \(outcome.exitCode): \(line)")
        }
    }

    var codexAlreadyThere: Bool {
        (try? String(contentsOf: Self.codexConfig, encoding: .utf8))?.contains("[mcp_servers.carry]") == true
    }

    /// Back `~/.codex/config.toml` up to `config.toml.bak`, then append the block.
    func appendToCodex() {
        let path = Self.codexConfig
        do {
            let existing = try String(contentsOf: path, encoding: .utf8)
            if existing.contains("[mcp_servers.carry]") {
                codexResult = "config.toml already has [mcp_servers.carry]; edit it by hand if it points elsewhere."
                return
            }
            let backup = path.deletingLastPathComponent().appendingPathComponent("config.toml.bak")
            try? FileManager.default.removeItem(at: backup)
            try FileManager.default.copyItem(at: path, to: backup)
            let joined = existing.hasSuffix("\n") || existing.isEmpty ? existing : existing + "\n"
            try (joined + "\n" + Self.codexBlock).write(to: path, atomically: true, encoding: .utf8)
            codexResult = "Appended. Backup at ~/.codex/config.toml.bak."
            AppLog.write("codex config: appended [mcp_servers.carry]")
        } catch {
            codexResult = "Could not write: \(error.localizedDescription)"
            AppLog.write("codex config failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Footer actions

    var runAtLogin: Bool { loginItemStatus == .enabled }

    func setRunAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemError = nil
        } catch {
            loginItemError = error.localizedDescription
        }
        loginItemStatus = SMAppService.mainApp.status
        AppLog.write("run at login \(on ? "on" : "off") → \(loginItemStatus.rawValue)"
                     + (loginItemError.map { " (\($0))" } ?? ""))
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func openContextFolder() {
        let path = status?.contextDir ?? CarryHome.context.path
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        NSWorkspace.shared.open(URL(fileURLWithPath: path, isDirectory: true))
    }
}
