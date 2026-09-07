import Foundation

/// What one sync came to.
struct SyncResult {
    let startedAt: Date
    let endedAt: Date
    let totals: [(String, Int)]
    let processed: [String: Int]
    let digestPath: URL?
    let heartbeatPath: URL?
    let errors: [(String, String)]

    var duration: TimeInterval { endedAt.timeIntervalSince(startedAt) }

    /// `synced  photos/screenshots +3  notes +1`
    var summaryLine: String {
        "synced  " + totals.map { "\($0.0) +\($0.1)" }.joined(separator: "  ")
    }
}

/// The engine: `carry sync` and `carry status --json` in-process (cli.py). One serial queue; the app awaits it.
final class Engine {
    static let shared = Engine()
    static let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"

    private let queue = DispatchQueue(label: "app.carry.engine", qos: .utility)

    private init() {}

    // MARK: - Sync (cli.py `sync`)

    /// Read every enabled source incrementally, process media (Pro), rewrite the digests, write the heartbeat.
    func sync(noProcess: Bool = false, noDigest: Bool = false, log: @escaping (String) -> Void = { _ in }) async -> Result<SyncResult, Error> {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: Result { try self.syncBlocking(noProcess: noProcess, noDigest: noDigest, log: log) })
            }
        }
    }

    private func syncBlocking(noProcess: Bool, noDigest: Bool, log: (String) -> Void) throws -> SyncResult {
        let started = Date()
        let cfg = Config.load()
        let store = try Store()
        defer { store.close() }
        let (enabled, decidedBy) = Config.effectiveSources(cfg)
        let backfill = PyTime.now().addingTimeInterval(-Double(Config.backfillDays(cfg)) * 86_400)
        var totals: [(String, Int)] = []
        var errors: [(String, String)] = []
        var ranPhotos = false
        for s in Sources.all where enabled[s.name] ?? false {
            do {
                if s.channel == .icloud {
                    guard let reader = Readers.reader(for: s.name) else { continue }
                    let ok: Bool, note: String
                    if s.name == "photos" || s.name == "screenshots" {
                        if ranPhotos { continue }
                        ranPhotos = true
                        (ok, note) = reader.available()
                        let n = ok ? try reader.collect(store: store, cfg: cfg, backfillStart: backfill, enabled: enabled) : 0
                        totals.append(("photos/screenshots", n))
                    } else {
                        (ok, note) = reader.available()
                        let n = ok ? try reader.collect(store: store, cfg: cfg, backfillStart: backfill, enabled: enabled) : 0
                        totals.append((s.name, n))
                    }
                    if !ok {
                        try store.setCursor(s.name, nil, count: 0, error: note)
                        log("  skip \(s.name): \(note)")
                    }
                } else {
                    var n = 0
                    if Container.present() {
                        switch s.name {
                        case "health": n = try Container.collectHealth(store: store, cfg: cfg, backfillStart: backfill)
                        case "location": n = try Container.collectLocation(store: store, cfg: cfg, backfillStart: backfill)
                        case "inbox": n = try Container.collectInbox(store: store, cfg: cfg, backfillStart: backfill)
                        default: break
                        }
                    }
                    totals.append((s.name, n))
                    if s.name == "health", !Container.haeDirectories(cfg).isEmpty {
                        totals.append(("health (Health Auto Export)", try Container.collectHealthAutoExport(store: store, cfg: cfg, backfillStart: backfill)))
                    }
                }
                store.commit()
            } catch {
                let message = "\(error)"
                try? store.setCursor(s.name, nil, count: 0, error: message)
                store.commit()
                errors.append((s.name, message))
                log("  error \(s.name): \(message)")
            }
        }
        log("synced  " + totals.map { "\($0.0) +\($0.1)" }.joined(separator: "  "))

        let pro = License.status()
        let proc = Config.effectiveProcessing(cfg)
        var processed: [String: Int] = [:]
        if !noProcess {
            processed = Processing.run(store: store, proc: proc, pro: pro.active, log: log)
            if pro.active, processed.values.contains(where: { $0 > 0 }) {
                log("processed  " + processed.filter { $0.value > 0 }.map { "\($0.key) \($0.value)" }.sorted().joined(separator: "  "))
            } else if !pro.active {
                let waiting = Processing.pendingCounts(store).values.reduce(0, +)
                if waiting > 0 { log("\(waiting) pictures/recordings are waiting for Pro to become text (\(pro.reason))") }
            }
        }
        var digestPath: URL? = nil
        if !noDigest {
            let written = try Digest.writeAll(store, enabled: enabled, pro: pro.active, decidedBy: decidedBy)
            digestPath = written.first
            if let first = written.first { log("→ \(first.path)") }
        }
        let hb = try Container.writeHeartbeat(store: store, version: Self.version, pro: pro.active,
                                              sourcesAppliedAt: Config.policyUpdatedAt(), lastDigestDate: PyTime.day(of: PyTime.now()))
        if let hb { log("→ heartbeat \(hb.lastPathComponent)") }
        return SyncResult(startedAt: started, endedAt: Date(), totals: totals, processed: processed, digestPath: digestPath,
                          heartbeatPath: hb, errors: errors)
    }

    // MARK: - Status (cli.py `_status_payload`)

    func status() async -> CarryStatus? {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: self.statusBlocking()) }
        }
    }

    func statusBlocking() -> CarryStatus? {
        let cfg = Config.load()
        guard let store = try? Store() else { return nil }
        defer { store.close() }
        let (enabled, decidedBy) = Config.effectiveSources(cfg)
        let counts = (try? store.counts()) ?? [:]
        let states = (try? store.syncStates()) ?? []
        let p = License.status()
        let m = Container.manifest()
        var rows: [SourceRow] = []
        for s in Sources.all {
            let st = states.first { $0.source == (s.name == "screenshots" ? "photos" : s.name) }
            rows.append(SourceRow(name: s.name, label: s.label, channel: s.channel, enabled: enabled[s.name] ?? s.defaultOn,
                                  items: counts[s.name] ?? 0, lastRun: st?.lastRun, error: st?.lastError.flatMap { $0.isEmpty ? nil : $0 }))
        }
        let lastSync = rows.compactMap(\.lastRun).max()
        let blocked = rows.filter { ($0.error ?? "").contains("Full Disk Access") }.map(\.label)
        var phone: PhoneInfo? = nil
        if let m {
            let d = m["device"]
            phone = PhoneInfo(name: d?["name"]?.string, os: d?["os"]?.string, appVersion: m["app_version"]?.string, updatedAt: m["updated_at"]?.string)
        }
        return CarryStatus(version: Self.version, home: CarryPaths.home.path, contextDir: CarryPaths.context.path, decidedBy: decidedBy,
                           pro: ProStatus(active: p.active, reason: p.reason, expiresAt: p.expiresAt), fda: FullDiskAccess.check(),
                           agentInstalled: LaunchAgent.isInstalled, appRunning: true, lastSyncAt: lastSync, sources: rows, phone: phone,
                           pending: Processing.pendingCounts(store), blocked: blocked)
    }

    // MARK: - Sources (cli.py `sources <name> --on|--off`)

    /// Switch a source on or off in config.toml. Returns the note the CLI prints when the phone's file wins.
    func setSource(_ name: String, enabled: Bool) async -> String? {
        await withCheckedContinuation { continuation in
            queue.async {
                var cfg = Config.load()
                var sources = cfg["sources"] ?? .object([])
                sources.set(name, .bool(enabled))
                cfg.set("sources", sources)
                do {
                    try Config.save(cfg)
                } catch {
                    continuation.resume(returning: "could not write config.toml: \(error.localizedDescription)")
                    return
                }
                let (_, by) = Config.effectiveSources(cfg)
                continuation.resume(returning: by == "phone"
                    ? "Saved locally, but the iPhone app's sources.json is present and wins. Change it on the phone." : nil)
            }
        }
    }

    /// The CLAUDE.md / AGENTS.md paragraph (cli.py `_agent_snippet`, with the MCP server named).
    static let agentSnippet =
        "My phone context lives in ~/.carry/context/ (written by Carry). Read latest.md at the start of a session when my "
        + "request touches my day, my health, places, notes, or things I shared from my phone. "
        + "For anything older, use the carry MCP server (search, recent, item) or `carry search \"<query>\"`."
}
