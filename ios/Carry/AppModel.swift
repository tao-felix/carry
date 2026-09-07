import Combine
import Foundation
import UIKit
import SwiftUI

/// One object behind every screen: the container, the control surface, capture, sync, Pro.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    enum Container: Equatable {
        case resolving
        case ready(ContainerLocation)
        /// iCloud Drive is off for Carry. Release builds only; DEBUG falls back to a local folder.
        case unavailable
    }

    @Published private(set) var container: Container = .resolving
    @Published private(set) var sources: SourcesConfig = .defaults
    @Published private(set) var sourcesSaving = false
    @Published private(set) var sourcesSavedAt: Date?
    @Published private(set) var heartbeat: Heartbeat?
    @Published private(set) var today = ContainerStore.TodayCounts()
    @Published private(set) var lastCapture: [SourceID: Date] = [:]
    @Published private(set) var isSyncing = false
    @Published private(set) var syncLine: String?
    @Published private(set) var syncFailed = false
    @Published private(set) var deletedAt: Date?
    @Published var welcomeDone: Bool {
        didSet { UserDefaults.standard.set(welcomeDone, forKey: "welcome.done") }
    }

    let health = HealthExporter()
    let location = LocationRecorder()
    let pro = ProStore()

    private(set) var store: ContainerStore?
    private var saveTask: Task<Void, Never>?
    private var lastAutoExport: Date?
    private var bootstrapped = false

    private init() {
        welcomeDone = UserDefaults.standard.bool(forKey: "welcome.done")
    }

    var containerLocation: ContainerLocation? {
        if case .ready(let location) = container { return location }
        return nil
    }

    // MARK: Lifecycle

    func bootstrap() async {
        guard !bootstrapped else { return }
        bootstrapped = true
        #if DEBUG
        if LaunchOptions.icloudOff {
            container = .unavailable
            return
        }
        #endif
        let resolved = await Task.detached(priority: .userInitiated) { ContainerStore.resolve() }.value
        guard let resolved else {
            container = .unavailable
            return
        }
        let store = ContainerStore(location: resolved)
        self.store = store
        try? await store.ensureLayout()
        #if DEBUG
        if LaunchOptions.demo {
            await Demo.seed(into: store, forceWelcome: LaunchOptions.forceWelcome)
            welcomeDone = UserDefaults.standard.bool(forKey: "welcome.done")
        }
        #endif
        if let saved = await store.readSources() {
            sources = saved
        } else {
            try? await store.writeSources(sources)
            sourcesSavedAt = Date()
        }
        try? await store.writeManifest(DeviceInfo.manifest())
        container = .ready(resolved)

        location.attach(store)
        location.enabled = sources.isEnabled(.location)
        location.start()
        if sources.isEnabled(.health), health.hasAsked, !LaunchOptions.demo { startHealthObservers() }
        await pro.start(store: store)
        #if DEBUG
        if LaunchOptions.e2e { await runEndToEnd(store: store) }
        #endif
        await refresh()
        BackgroundSync.schedule()
    }

    #if DEBUG
    /// End-to-end fixture: the same code paths a user's taps go through, without the taps.
    private func runEndToEnd(store: ContainerStore) async {
        welcomeDone = true
        setSource(.messages, enabled: true)
        let link = InboxDraft(payload: .url(URL(string: "https://github.com/screenpipe/screenpipe")!, text: nil),
                              title: "screenpipe: open source screen memory", note: "compare with Carry, they charge $25/mo")
        _ = try? await InboxWriter.write(link, to: store)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 600))
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1200, height: 600))
            let style = NSMutableParagraphStyle()
            style.alignment = .left
            let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 64, weight: .semibold),
                                                        .foregroundColor: UIColor.black, .paragraphStyle: style]
            "Carry end-to-end test\n把手机里的你，带到 Agent 面前\nInvoice #9911 · Total $1,284.00".draw(in: CGRect(x: 60, y: 120, width: 1080, height: 400), withAttributes: attrs)
        }
        if let png = image.pngData() {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("carry-e2e.png")
            try? png.write(to: tmp)
            _ = try? await InboxWriter.write(InboxDraft(payload: .image(tmp), note: "read this later"), to: store)
        }
        await syncNow()
        try? await Task.sleep(nanoseconds: 1_500_000_000)
    }
    #endif

    /// Foreground: refresh the screen and, at most every 15 minutes, export Health.
    func foreground() async {
        guard bootstrapped, store != nil else { return }
        await refresh()
        var due = lastAutoExport.map { Date().timeIntervalSince($0) > 15 * 60 } ?? true
        #if DEBUG
        if LaunchOptions.demo { due = false }
        #endif
        if due, sources.isEnabled(.health), health.hasAsked {
            lastAutoExport = Date()
            await exportHealth()
        }
        BackgroundSync.schedule()
    }

    /// BGAppRefreshTask and HealthKit background delivery both land here.
    func backgroundSync() async {
        if !bootstrapped { await bootstrap() }
        guard sources.isEnabled(.health), health.hasAsked else { return }
        await exportHealth()
    }

    func refresh() async {
        guard let store else { return }
        heartbeat = await store.latestHeartbeat()
        today = await store.todayCounts()
        var captures: [SourceID: Date] = [:]
        for id in SourceID.appSources {
            if let date = AppGroup.lastCapture(id) { captures[id] = date }
        }
        lastCapture = captures
        if syncLine == nil { syncLine = UserDefaults.standard.string(forKey: "sync.lastLine") }
    }

    // MARK: The control surface (sources.json, §3)

    func setSource(_ id: SourceID, enabled: Bool) {
        sources.setEnabled(id, enabled)
        switch id {
        case .location:
            location.enabled = enabled
            if enabled { location.start() } else { location.stop() }
        case .health:
            if enabled { startHealthObservers() } else { health.disableBackgroundDelivery() }
        default:
            break
        }
        scheduleSave()
    }

    func setHealthType(_ type: HealthType, enabled: Bool) {
        sources.setHealthType(type, enabled)
        scheduleSave()
    }

    func setProcessing(ocr: Bool? = nil, transcribe: Bool? = nil) {
        if let ocr { sources.processing.ocr = ocr }
        if let transcribe { sources.processing.transcribe = transcribe }
        scheduleSave()
    }

    /// Writes `sources.json` once, one second after the last change.
    private func scheduleSave() {
        sourcesSaving = true
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled, let self, let store = self.store else { return }
            try? await store.writeSources(self.sources)
            self.sourcesSaving = false
            self.sourcesSavedAt = Date()
        }
    }

    func sourcesSaveLine(now: Date) -> String {
        if sourcesSaving { return "sources.json · saving…" }
        if let at = sourcesSavedAt { return "sources.json · saved \(RelativeTime.string(since: at, now: now))" }
        return "sources.json · on your iCloud Drive"
    }

    // MARK: Permissions

    /// One system prompt for all nine types, then the first backfill.
    func requestHealthAccess() async {
        do {
            try await health.requestAuthorization()
        } catch {
            syncLine = "Health: \(error.localizedDescription)"
            syncFailed = true
            return
        }
        setSource(.health, enabled: true)
        await exportHealth()
    }

    func requestLocationAccess() {
        location.requestAuthorization()
        if !sources.isEnabled(.location) { setSource(.location, enabled: true) }
    }

    private func startHealthObservers() {
        health.enableBackgroundDelivery(sources.healthTypes) { done in
            Task { @MainActor in
                await AppModel.shared.exportHealth()
                done()
            }
        }
    }

    // MARK: Sync

    /// "Sync now": Health export plus one location point if due. Reports in one mono line.
    func syncNow() async {
        guard !isSyncing, let store else { return }
        isSyncing = true
        syncFailed = false
        var parts: [String] = []
        if sources.isEnabled(.health) {
            syncLine = "Reading Health…"
            do {
                let result = try await health.export(sources.healthTypes, to: store)
                parts.append(plural(result.samples, "health sample"))
            } catch {
                await finishSync("Health: \(error.localizedDescription)", failed: true)
                return
            }
        }
        if sources.isEnabled(.location) {
            syncLine = "Writing location…"
            let written = await location.syncNow()
            parts.append(plural(written.visits, "visit"))
            if written.points > 0 { parts.append(plural(written.points, "point")) }
        }
        let line = parts.isEmpty ? "Nothing to sync: Health and Location are off" : "Wrote " + parts.joined(separator: ", ")
        await finishSync(line, failed: false)
    }

    private func exportHealth() async {
        guard !isSyncing, let store else { return }
        isSyncing = true
        syncFailed = false
        do {
            let result = try await health.export(sources.healthTypes, to: store)
            await finishSync("Wrote " + plural(result.samples, "health sample"), failed: false)
        } catch {
            await finishSync("Health: \(error.localizedDescription)", failed: true)
        }
    }

    private func finishSync(_ line: String, failed: Bool) async {
        syncLine = statusJoin([line, TimeText.time(Date())])
        syncFailed = failed
        if !failed { UserDefaults.standard.set(syncLine, forKey: "sync.lastLine") }
        isSyncing = false
        await refresh()
    }

    // MARK: Delete

    /// Removes every file Carry wrote, then re-creates the layout with `sources.json` and `manifest.json`
    /// (no personal data in either; without them the Mac would fall back to its own defaults).
    func deleteEverything() async {
        guard let store else { return }
        try? await store.deleteEverything()
        health.resetAnchors()
        for id in SourceID.appSources { AppGroup.clearCapture(id) }
        UserDefaults.standard.removeObject(forKey: "sync.lastLine")
        syncLine = nil
        try? await store.writeSources(sources)
        try? await store.writeManifest(DeviceInfo.manifest())
        await pro.refreshEntitlement()
        deletedAt = Date()
        await refresh()
    }
}
