import AppKit
import Observation
import ServiceManagement
import SwiftUI

/// What the last sync this app ran came to.
struct SyncOutcome {
    let endedAt: Date
    let exitCode: Int32
    let tail: String
    var ok: Bool { exitCode == 0 }
}

/// Is the engine there and does it speak our JSON?
enum EngineState: Equatable {
    case ready
    case missing
    case outdated(version: String)
    case failed(String)
}

/// All app state and every action. One instance, on the main actor. Views read it; timers and the CLI feed it.
@MainActor @Observable
final class AppModel {
    static let shared = AppModel()

    static let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    static let scheduleChoices = [5, 15, 30, 60]
    private static let scheduleKey = "scheduleMinutes"
    private static let launchedKey = "hasLaunchedBefore"
    private static let proOverrideKey = "CARRY_PRO"

    // Engine
    private(set) var cliPath: String?
    private(set) var cliVersion: String?
    private(set) var engine: EngineState = .missing
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

    // Bookkeeping
    private var timer: Timer?
    private var lastPresenceWrite: Date?
    private var tookOverScheduling = false
    /// DEBUG: render the "not granted" Full Disk Access card and a sample iPhone for screenshots.
    var previewMode = false

    private init() {
        let stored = UserDefaults.standard.integer(forKey: Self.scheduleKey)
        scheduleMinutes = Self.scheduleChoices.contains(stored) ? stored : 15
    }

    // MARK: - Lifecycle

    func start() {
        AppLog.write("app \(Self.appVersion) launched, pid \(ProcessInfo.processInfo.processIdentifier)")
        writePresence()
        locateCLI()
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
        Presence.remove()
        AppLog.write("app quit")
    }

    /// Open the window on the first launch ever, and whenever something needs the user (no CLI, no FDA).
    var shouldOpenWindowAtLaunch: Bool {
        let first = !UserDefaults.standard.bool(forKey: Self.launchedKey)
        UserDefaults.standard.set(true, forKey: Self.launchedKey)
        return first || cliPath == nil || !fdaGranted
    }

    private func boot() async {
        await refreshStatus()
        if cliPath != nil { await sync(reason: "launch") }
    }

    private func tick() async {
        let now = Date()
        if lastPresenceWrite.map({ now.timeIntervalSince($0) >= 60 }) ?? true { writePresence() }
        if cliPath == nil {
            // The install card asks the user to run `uv tool install carry-context`; look again every 5 s.
            locateCLI()
            if cliPath != nil {
                await refreshStatus()
                await sync(reason: "carry installed")
            }
            return
        }
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

    private func locateCLI() {
        let found = CarryCLI.locate()
        if found != cliPath { AppLog.write(found.map { "carry found at \($0)" } ?? "carry not found") }
        cliPath = found
        if found == nil { engine = .missing }
    }

    /// The developer override `CARRY_PRO=1`, kept when the app takes over from a LaunchAgent that carried it.
    private var extraEnvironment: [String: String] {
        UserDefaults.standard.string(forKey: Self.proOverrideKey) == "1" ? ["CARRY_PRO": "1"] : [:]
    }

    // MARK: - Status

    func refreshStatus() async {
        guard let cli = cliPath, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let result = await CarryCLI.run(cli, ["status", "--json"], extraEnvironment: extraEnvironment, timeout: 30)
        lastStatusRefresh = Date()
        if let parsed = decodeStatus(result) {
            status = parsed
            engine = .ready
            cliVersion = parsed.version ?? cliVersion
            sourceOverrides = [:]
            fdaGranted = (parsed.fda ?? false) || FullDiskAccess.check()
            heartbeat = HeartbeatFile.load()
            if parsed.agentInstalled == true { await takeOverScheduling(cli) }
        } else {
            let version = await CarryCLI.version(cli)
            cliVersion = version
            let complaint = result.stderr + result.stdout
            if complaint.contains("--json") || complaint.contains("No such option") {
                engine = .outdated(version: version ?? "?")
            } else {
                engine = .failed(result.tail.isEmpty ? "exit \(result.exitCode)" : result.tail)
            }
            AppLog.write("status failed, exit \(result.exitCode)", detail: result.lastLines(8))
        }
        loginItemStatus = SMAppService.mainApp.status
    }

    private func decodeStatus(_ result: CommandResult) -> CarryStatus? {
        guard result.ok, let data = result.stdout.data(using: .utf8) else { return nil }
        return try? JSONDecoder.carry.decode(CarryStatus.self, from: data)
    }

    /// While this app runs it is the scheduler, and every sync it starts inherits its Full Disk Access.
    /// The CLI's LaunchAgent (bare python, no FDA) would only duplicate the work, so remove it once.
    private func takeOverScheduling(_ cli: String) async {
        guard !tookOverScheduling else { return }
        tookOverScheduling = true
        if LaunchAgent.carriesProOverride { UserDefaults.standard.set("1", forKey: Self.proOverrideKey) }
        let result = await CarryCLI.run(cli, ["agent", "uninstall"], timeout: 30)
        AppLog.write(result.ok ? "LaunchAgent removed; Carry for Mac schedules the sync now"
                               : "LaunchAgent not removed, exit \(result.exitCode)", detail: result.lastLines(4))
        if result.ok { status?.agentInstalled = false }
    }

    // MARK: - Sync

    func sync(reason: String) async {
        guard !isSyncing, let cli = cliPath else { return }
        isSyncing = true
        let started = Date()
        syncStartedAt = started
        lastSyncStartedAt = started
        AppLog.write("sync start (\(reason))")
        let result = await CarryCLI.run(cli, ["sync", "--quiet"], extraEnvironment: extraEnvironment)
        isSyncing = false
        lastSync = SyncOutcome(endedAt: Date(), exitCode: result.exitCode, tail: String(result.tail.prefix(120)))
        AppLog.write("sync exit \(result.exitCode) in \(String(format: "%.1f", result.duration)) s",
                     detail: result.lastLines())
        await refreshStatus()
    }

    /// The mono line under the title and in the menu.
    var statusLine: (text: String, color: Color) {
        switch engine {
        case .missing:
            return ("carry is not installed on this Mac", Theme.warn)
        case .outdated(let version):
            return ("carry \(version) is older than this app · \(CarryCLI.upgradeCommand)", Theme.warn)
        case .failed(let message):
            return ("carry status failed · \(message)", Theme.warn)
        case .ready:
            break
        }
        if isSyncing, let started = syncStartedAt {
            return ("Syncing… since \(TimeText.short(started))", Theme.ink)
        }
        if let last = lastSync, !last.ok {
            let detail = last.tail.isEmpty ? "" : " · \(last.tail)"
            return ("Sync failed \(TimeText.short(last.endedAt)) · exit \(last.exitCode)\(detail)", Theme.warn)
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
                if await self.probeFDA() {
                    self.fdaWaiting = false
                    self.fdaGranted = true
                    AppLog.write("FDA granted")
                    await self.fdaBecameGranted()
                    return
                }
            }
            self?.fdaWaiting = false
        }
    }

    func stopWaitingForFDA() {
        fdaWaiting = false
    }

    /// macOS applies a new FDA grant to processes started afterwards, and may keep this process's own
    /// verdict cached until relaunch. So ask the CLI too: a fresh child sees the new state.
    private func probeFDA() async -> Bool {
        if FullDiskAccess.check() { return true }
        guard let cli = cliPath, !isSyncing else { return false }
        let result = await CarryCLI.run(cli, ["status", "--json"], extraEnvironment: extraEnvironment, timeout: 20)
        guard let parsed = decodeStatus(result) else { return false }
        status = parsed
        return parsed.fda == true
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
        guard let cli = cliPath, !decidedOnPhone else { return }
        sourceOverrides[name] = enabled
        Task {
            let result = await CarryCLI.run(cli, ["sources", name, enabled ? "--on" : "--off"],
                                            extraEnvironment: extraEnvironment, timeout: 30)
            AppLog.write("sources \(name) \(enabled ? "on" : "off"), exit \(result.exitCode)")
            sourceNote = result.ok ? nil : result.tail
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
            return Heartbeat(host: HeartbeatFile.hostName, carryVersion: cliVersion, lastSyncAt: RFC3339.string())
        }
        return heartbeat
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
