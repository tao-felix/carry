import Foundation

/// The iCloud container written by the Carry iOS app: health, location, inbox, manifest, license,
/// plus the heartbeat the Mac writes back so the phone can say "Mac read this 12 minutes ago" (container.py).
enum Container {
    static var dir: URL { CarryPaths.container }

    static func present() -> Bool { FileManager.default.fileExists(atPath: dir.path) }

    static func manifest() -> JSON? {
        let p = dir.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: p) else { return nil }
        return JSON.parse(data)
    }

    /// `icloud_download(path)`: ask iCloud to materialise placeholders below `path`. Cheap, safe every sync.
    static func download(_ path: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path.path) else { return }
        try? fm.startDownloadingUbiquitousItem(at: path)
        if let e = fm.enumerator(at: path, includingPropertiesForKeys: [.isUbiquitousItemKey], options: [.skipsHiddenFiles]) {
            for case let url as URL in e {
                if url.lastPathComponent.hasSuffix(".icloud") || url.lastPathComponent.hasPrefix(".") {
                    try? fm.startDownloadingUbiquitousItem(at: url)
                }
            }
        }
        // Placeholders are hidden files (".name.icloud"); a second pass without skipping catches them.
        if let e = fm.enumerator(at: path, includingPropertiesForKeys: nil) {
            for case let url as URL in e where url.pathExtension == "icloud" {
                try? fm.startDownloadingUbiquitousItem(at: url)
            }
        }
    }

    private static func jsonlFiles(_ sub: String) -> [URL] {
        Readers.glob(dir.appendingPathComponent(sub, isDirectory: true), suffix: ".jsonl")
    }

    /// Per-file byte offsets, stored as JSON in the cursor.
    private static func lineCursor(_ store: Store, _ key: String) -> [(String, JSON)] {
        guard let raw = try? store.getCursor(key), let j = JSON.parse(raw), case .object(let pairs) = j else { return [] }
        return pairs
    }

    private static func cursorValue(_ pairs: [(String, JSON)], _ key: String) -> Int {
        Int(pairs.first { $0.0 == key }?.1.int ?? 0)
    }

    private static func setCursorValue(_ pairs: inout [(String, JSON)], _ key: String, _ value: JSON) {
        if let i = pairs.firstIndex(where: { $0.0 == key }) { pairs[i].1 = value } else { pairs.append((key, value)) }
    }

    /// `_read_new_lines`: JSON objects after `offset`; if the file shrank it was replaced, start over.
    private static func readNewLines(_ path: URL, offset: Int) -> ([JSON], Int) {
        guard let data = try? Data(contentsOf: path) else { return ([], offset) }
        let from = offset > data.count ? 0 : offset
        var out: [JSON] = []
        let text = String(decoding: data[from...], as: UTF8.self)
        for line in Py.splitlines(text) {
            let trimmed = Py.strip(line)
            if trimmed.isEmpty { continue }
            if let j = JSON.parse(trimmed) { out.append(j) }
        }
        return (out, data.count)
    }

    /// `f"{v} {u}".strip()` for numbers, `f"{v}"` for strings.
    static func valueText(_ v: JSON?, _ u: String) -> String {
        let v = v ?? .null
        if case .string(let s) = v { return s }
        return Py.strip("\(v.pyStr) \(u)")
    }

    static func collectHealth(store: Store, cfg: JSON, backfillStart: Date) throws -> Int {
        download(dir.appendingPathComponent("health"))
        var cursors = lineCursor(store, "health")
        var new = 0
        for f in jsonlFiles("health") {
            let (recs, size) = readNewLines(f, offset: cursorValue(cursors, f.lastPathComponent))
            for r in recs {
                guard let start = PyTime.parseISO(r["start"]?.string) else { continue }
                let end = PyTime.parseISO(r["end"]?.string)
                let t = r["t"]?.string ?? "unknown"
                let u = r["u"]?.string ?? ""
                let src = r["src"]?.string ?? ""
                let text = valueText(r["v"], u)
                var meta: JSON = .object([("v", r["v"] ?? .null), ("u", .string(u)), ("src", .string(src))])
                if let extra = r["meta"], case .object = extra { meta.update(extra) }
                if try store.upsert(id: Util.stableID("health", t, r["start"], r["end"], src), source: "health", kind: t, ts: start,
                                    tsEnd: end, title: t, text: text, meta: meta, device: "iphone") {
                    new += 1
                }
            }
            setCursorValue(&cursors, f.lastPathComponent, .num(size))
        }
        try store.setCursor("health", JSON.object(cursors).dumps(), count: new)
        return new
    }

    static func collectLocation(store: Store, cfg: JSON, backfillStart: Date) throws -> Int {
        download(dir.appendingPathComponent("location"))
        var cursors = lineCursor(store, "location")
        var new = 0
        for f in jsonlFiles("location") {
            let (recs, size) = readNewLines(f, offset: cursorValue(cursors, f.lastPathComponent))
            for r in recs {
                let kind = r["kind"]?.string ?? "point"
                let ts: Date?
                let end: Date?
                if kind == "visit" {
                    ts = PyTime.parseISO(r["arrive"]?.string)
                    end = PyTime.parseISO(r["depart"]?.string)
                } else {
                    ts = PyTime.parseISO(r["ts"]?.string)
                    end = nil
                }
                guard let ts else { continue }
                let place = r["place"]
                let lat = r["lat"] ?? .null, lon = r["lon"] ?? .null
                let meta: JSON = .object([("lat", lat), ("lon", lon), ("acc_m", r["acc_m"] ?? .null), ("place", place ?? .null)])
                let when: JSON? = (r["arrive"]?.truthy == true ? r["arrive"] : nil) ?? r["ts"]
                let title = (place?.truthy == true ? place?.string : nil) ?? "\(lat.pyStr), \(lon.pyStr)"
                if try store.upsert(id: Util.stableID("loc", kind, when, lat, lon), source: "location", kind: kind, ts: ts, tsEnd: end,
                                    title: title, meta: meta, device: "iphone") {
                    new += 1
                }
            }
            setCursorValue(&cursors, f.lastPathComponent, .num(size))
        }
        try store.setCursor("location", JSON.object(cursors).dumps(), count: new)
        return new
    }

    static func collectInbox(store: Store, cfg: JSON, backfillStart: Date) throws -> Int {
        let d = dir.appendingPathComponent("inbox", isDirectory: true)
        download(d)
        guard FileManager.default.fileExists(atPath: d.path) else {
            try store.setCursor("inbox", nil, count: 0)
            return 0
        }
        var new = 0
        for f in Readers.glob(d, suffix: ".json") {
            guard let data = try? Data(contentsOf: f), let r = JSON.parse(data) else { continue }
            let ts = PyTime.parseISO(r["ts"]?.string) ?? PyTime.now()
            let kind = r["kind"]?.string ?? "text"
            let rawText = r["text"]?.string ?? ""
            let stripped = Py.strip(rawText)
            let text: String? = stripped.isEmpty ? nil : stripped // the note stays in meta; the digest prints it on its own line
            let fileName = r["file"]?.string
            let attachment = fileName.flatMap { $0.isEmpty ? nil : d.appendingPathComponent($0) }
            let meta: JSON = .object([("url", r["url"] ?? .null), ("from_app", r["from_app"] ?? .null), ("note", r["note"] ?? .null), ("file", r["file"] ?? .null)])
            let titleRaw = Py.strip(r["title"]?.string ?? "")
            let title = !titleRaw.isEmpty ? titleRaw
                : (r["url"]?.truthy == true ? r["url"]!.pyStr
                    : (Py.strip(Py.prefix(rawText, 60)).isEmpty ? Py.capitalize(kind) : Py.strip(Py.prefix(rawText, 60))))
            let idPart: Any? = (r["id"]?.truthy == true ? r["id"]?.pyStr : nil) ?? f.deletingPathExtension().lastPathComponent
            let path = attachment.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0.path : nil }
            if try store.upsert(id: Util.stableID("inbox", idPart), source: "inbox", kind: kind, ts: ts, title: title, text: text,
                                meta: meta, path: path, device: "iphone") {
                new += 1
            }
        }
        try store.setCursor("inbox", nil, count: new)
        return new
    }

    /// `heartbeat/<host>.json`, the same host rule as the CLI (`socket.gethostname()` before the first dot).
    static var hostName: String {
        var buffer = [CChar](repeating: 0, count: 256)
        gethostname(&buffer, buffer.count - 1)
        let full = String(cString: buffer)
        return full.split(separator: ".").first.map(String.init) ?? full
    }

    @discardableResult
    static func writeHeartbeat(store: Store, version: String, pro: Bool, sourcesAppliedAt: String?, lastDigestDate: String?) throws -> URL? {
        guard present() else { return nil }
        let d = dir.appendingPathComponent("heartbeat", isDirectory: true)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        let host = hostName
        let counts = try store.counts()
        let payload: JSON = .object([
            ("host", .string(host)),
            ("carry_version", .string(version)),
            ("last_sync_at", .string(PyTime.iso(PyTime.now()))),
            ("last_digest_date", .str(lastDigestDate)),
            ("counts", .object(["health", "location", "inbox", "photos", "screenshots", "notes", "voice_memos"].map { ($0, .num(counts[$0] ?? 0)) })),
            ("pro", .bool(pro)),
            ("sources_applied_at", .str(sourcesAppliedAt)),
        ])
        let p = d.appendingPathComponent("\(host).json")
        let tmp = d.appendingPathComponent("\(host).json.tmp")
        try payload.dumps(indent: 2).write(to: tmp, atomically: false, encoding: .utf8)
        _ = try FileManager.default.replaceItemAt(p, withItemAt: tmp)
        return p
    }

    // MARK: - Health Auto Export fallback
    // Some people already run Health Auto Export (HealthyApps) with an iCloud Drive automation. Its JSON lands in
    // iCloud Drive › AutoExport › <automation>/ . Reading it is a fallback for when the Carry app's own HealthKit
    // channel is not available (unsigned build, App Review outcome, or the user simply prefers HAE).

    static let haeDirs: [URL] = [
        Readers.home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/AutoExport", isDirectory: true),
    ]

    static let haeNames: [String: (String, String?)] = [
        "step_count": ("steps", "count"), "heart_rate": ("heart_rate", "bpm"), "resting_heart_rate": ("resting_heart_rate", "bpm"),
        "heart_rate_variability": ("hrv", "ms"), "active_energy": ("active_energy", "kcal"), "weight_body_mass": ("body_mass", nil),
        "blood_oxygen_saturation": ("blood_oxygen", "ratio"),
    ]

    static func haeDirectories(_ cfg: JSON) -> [URL] {
        var dirs: [URL] = []
        if let extra = cfg["carry"]?["health_auto_export_dir"]?.string, !extra.isEmpty {
            dirs.append(URL(fileURLWithPath: (extra as NSString).expandingTildeInPath, isDirectory: true))
        }
        dirs += haeDirs
        let mobile = Readers.home.appendingPathComponent("Library/Mobile Documents", isDirectory: true)
        if let names = try? FileManager.default.contentsOfDirectory(atPath: mobile.path) {
            for n in names where n.contains("HealthAutoExport") {
                dirs.append(mobile.appendingPathComponent(n).appendingPathComponent("Documents", isDirectory: true))
            }
        }
        return dirs.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func haeDate(_ v: JSON?) -> Date? {
        guard let v else { return nil }
        let s = v.pyStr
        return PyTime.parseHAE(s)
    }

    /// `hae_records(payload)`: one Health Auto Export JSON document → DATA-CONTRACT §4 records.
    static func haeRecords(_ payload: JSON) -> [JSON] {
        var out: [JSON] = []
        let data = payload["data"] ?? payload
        func rec(_ t: String, _ start: Date, _ end: Date, _ v: JSON, _ u: String, _ src: String, meta: JSON? = nil) -> JSON {
            var pairs: [(String, JSON)] = [("t", .string(t)), ("start", .string(PyTime.iso(start))), ("end", .string(PyTime.iso(end))),
                                           ("v", v), ("u", .string(u)), ("src", .string(src))]
            if let meta { pairs.append(("meta", meta)) }
            return .object(pairs)
        }
        for metric in data["metrics"]?.array ?? [] {
            let name = metric["name"]?.string
            let units = metric["units"]?.string ?? ""
            for pt in metric["data"]?.array ?? [] {
                guard let when = haeDate(pt["date"] ?? .string("")) else { continue }
                let src = (pt["source"]?.truthy == true ? pt["source"]?.string : nil) ?? "Health Auto Export"
                if name == "sleep_analysis" {
                    let start = haeDate((pt["sleepStart"]?.truthy == true ? pt["sleepStart"] : nil) ?? (pt["inBedStart"]?.truthy == true ? pt["inBedStart"] : nil) ?? .string("")) ?? when
                    var cursor = start
                    for (stage, key) in [("core", "core"), ("deep", "deep"), ("rem", "rem"), ("awake", "awake")] {
                        guard let hours = pt[key], hours.truthy, let h = hours.double else { continue }
                        let end = cursor.addingTimeInterval(h * 3600)
                        out.append(rec("sleep", cursor, end, .string(stage), "stage", src, meta: .object([("approx", .bool(true))])))
                        cursor = end
                    }
                    let anyStage = ["core", "deep", "rem"].contains { pt[$0]?.truthy == true }
                    if !anyStage, let asleep = pt["asleep"], asleep.truthy, let h = asleep.double {
                        out.append(rec("sleep", start, start.addingTimeInterval(h * 3600), .string("asleepUnspecified"), "stage", src,
                                       meta: .object([("approx", .bool(true))])))
                    }
                    continue
                }
                guard let name, let (t, unit) = haeNames[name] else { continue }
                var value: JSON? = name == "heart_rate" ? (pt["Avg"] ?? pt["qty"]) : pt["qty"]
                if value == nil || value?.isNull == true { continue }
                if name == "blood_oxygen_saturation", let d = value?.double, d > 1.5 { value = .double(d / 100.0) }
                out.append(rec(t, when, when, value ?? .null, unit ?? units, src))
            }
        }
        for w in data["workouts"]?.array ?? [] {
            guard let start = haeDate(w["start"] ?? .string("")) else { continue }
            let end = haeDate(w["end"] ?? .string(""))
            var meta: JSON = .object([])
            if let dist = w["distance"], case .object = dist, let qty = dist["qty"], !qty.isNull, let q = qty.double {
                let units = (dist["units"]?.pyStr ?? "").lowercased()
                let factor: Double = ["km", "kilometer", "kilometers"].contains(units) ? 1000 : 1
                meta.set("distance_m", .double(q * factor))
            }
            if let energy = w["activeEnergyBurned"] ?? w["activeEnergy"], case .object = energy, let qty = energy["qty"], !qty.isNull, let q = qty.double {
                meta.set("energy_kcal", .double(q))
            }
            let name = (w["name"]?.truthy == true ? w["name"]?.pyStr : nil) ?? "workout"
            let src = (w["source"]?.truthy == true ? w["source"]?.pyStr : nil) ?? "Health Auto Export"
            out.append(rec("workout", start, end ?? start, .string(name), "type", src, meta: meta))
        }
        return out
    }

    static func collectHealthAutoExport(store: Store, cfg: JSON, backfillStart: Date) throws -> Int {
        var new = 0
        var cursors = lineCursor(store, "health_hae")
        let fm = FileManager.default
        for d in haeDirectories(cfg) {
            download(d)
            // Keys are the paths as configured (Python's `str(f)`), symlinks left alone: /tmp stays /tmp.
            var files: [URL] = []
            if let e = fm.enumerator(atPath: d.path) {
                for case let rel as String in e where rel.hasSuffix(".json") {
                    files.append(URL(fileURLWithPath: d.path + "/" + rel))
                }
            }
            files.sort { $0.path.utf8.lexicographicallyPrecedes($1.path.utf8) }
            for f in files {
                let key = f.path
                guard let attrs = try? fm.attributesOfItem(atPath: f.path) else { continue }
                let mtime = Int((attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)
                let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
                let stamp = "\(mtime):\(size)"
                if cursors.first(where: { $0.0 == key })?.1.string == stamp { continue }
                guard let data = try? Data(contentsOf: f), let payload = JSON.parse(data) else { continue }
                for r in haeRecords(payload) {
                    guard let start = PyTime.parseISO(r["start"]?.string), start >= backfillStart else { continue }
                    let end = PyTime.parseISO(r["end"]?.string)
                    let u = r["u"]?.string ?? ""
                    let src = r["src"]?.string ?? ""
                    let t = r["t"]?.string ?? ""
                    let text = valueText(r["v"], u)
                    var meta: JSON = .object([("v", r["v"] ?? .null), ("u", .string(u)), ("src", .string(src)), ("via", .string("health-auto-export"))])
                    if let extra = r["meta"] { meta.update(extra) }
                    if try store.upsert(id: Util.stableID("health", t, r["start"], r["end"], src), source: "health", kind: t, ts: start,
                                        tsEnd: end, title: t, text: text, meta: meta, device: "iphone") {
                        new += 1
                    }
                }
                setCursorValue(&cursors, key, .string(stamp))
            }
        }
        try store.setCursor("health_hae", JSON.object(cursors).dumps(), count: new)
        return new
    }
}
