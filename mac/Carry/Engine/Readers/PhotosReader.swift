import Foundation

/// Photos and screenshots from the iCloud Photos library (Photos.sqlite, read-only, never copied).
enum PhotosReader: Reader {
    static let library = Readers.home.appendingPathComponent("Pictures/Photos Library.photoslibrary", isDirectory: true)
    static let db = library.appendingPathComponent("database/Photos.sqlite")
    static let screenshotSubtype: Int64 = 10

    static func available() -> (Bool, String) {
        guard FileManager.default.fileExists(atPath: db.path) else { return (false, "No Photos library at ~/Pictures") }
        do {
            let con = try SQLiteDB.openReadOnly(db.path)
            defer { con.close() }
            let n = try con.scalar("select count(*) from ZASSET where ZTRASHEDSTATE=0")
            return (true, Readers.countNote(n, "assets"))
        } catch {
            return (false, "Cannot read Photos.sqlite (\(error)). Grant Full Disk Access.")
        }
    }

    /// One listing per derivatives sub-folder per run (they hold thousands of files).
    private static var listings: [String: [String]] = [:]

    /// Prefer the medium derivative (JPEG, always readable); fall back to the original.
    static func imagePath(uuid: String, directory: String, filename: String) -> String? {
        let derivDir = library.appendingPathComponent("resources/derivatives", isDirectory: true)
            .appendingPathComponent(String(uuid.prefix(1)), isDirectory: true)
        let names: [String]
        if let cached = listings[derivDir.path] {
            names = cached
        } else {
            names = ((try? FileManager.default.contentsOfDirectory(atPath: derivDir.path)) ?? []).sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
            listings[derivDir.path] = names
        }
        if !names.isEmpty || FileManager.default.fileExists(atPath: derivDir.path) {
            let candidates = names.filter { $0.hasPrefix("\(uuid)_1_105_c.") } + names.filter { $0.hasPrefix("\(uuid)_1_101_o.") }
            if let first = candidates.first { return derivDir.appendingPathComponent(first).path }
        }
        let orig = library.appendingPathComponent("originals", isDirectory: true).appendingPathComponent(directory).appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: orig.path) ? orig.path : nil
    }

    static func collect(store: Store, cfg: JSON, backfillStart: Date, enabled: [String: Bool]) throws -> Int {
        let con = try SQLiteDB.openReadOnly(db.path)
        defer { con.close() }
        listings = [:]
        defer { listings = [:] }
        let cursor = try store.getCursor("photos")
        let whereClause: String
        let arg: Double
        if let cursor, let c = Double(cursor) {
            whereClause = "a.ZADDEDDATE > ?"
            arg = c
        } else {
            whereClause = "a.ZDATECREATED > ?"
            arg = PyTime.dateToApple(backfillStart)
        }
        let rows = try con.query(
            """
            select a.ZUUID, a.ZFILENAME, a.ZDIRECTORY, a.ZDATECREATED, a.ZADDEDDATE, a.ZKIND, a.ZKINDSUBTYPE,
                      a.ZLATITUDE, a.ZLONGITUDE, a.ZFAVORITE, aa.ZORIGINALFILENAME, d.ZLONGDESCRIPTION
               from ZASSET a
               left join ZADDITIONALASSETATTRIBUTES aa on aa.ZASSET = a.Z_PK
               left join ZASSETDESCRIPTION d on d.ZASSETATTRIBUTES = aa.Z_PK
               where a.ZTRASHEDSTATE=0 and a.ZHIDDEN=0 and \(whereClause)
               order by a.ZADDEDDATE
            """, [.double(arg)])
        var new = 0
        var maxAdded: Double = cursor.flatMap { Double($0) } ?? 0.0
        for r in rows {
            let isShot = r["ZKINDSUBTYPE"].int == screenshotSubtype
            let source = isShot ? "screenshots" : "photos"
            if !(enabled[source] ?? true) {
                maxAdded = max(maxAdded, r["ZADDEDDATE"].double ?? 0)
                continue
            }
            guard let ts = PyTime.appleToDate(r["ZDATECREATED"]) else { continue }
            let kind = isShot ? "screenshot" : (r["ZKIND"].int == 1 ? "video" : "photo")
            let uuid = r["ZUUID"].string ?? ""
            var meta: JSON = .object([
                ("uuid", r["ZUUID"].json),
                ("original_filename", r["ZORIGINALFILENAME"].json),
                ("favorite", .bool(r["ZFAVORITE"].truthy)),
            ])
            // `round(v, 5)` keeps an int an int and rounds a float.
            func rounded(_ v: SQLValue) -> JSON? {
                switch v {
                case .int(let i): return .int(i)
                case .double(let d): return .double(Py.round(d, 5))
                default: return nil
                }
            }
            if let lat = r["ZLATITUDE"].double, let lon = r["ZLONGITUDE"].double, !r["ZLATITUDE"].isNull, !r["ZLONGITUDE"].isNull,
               lat > -180, lon > -180, let rlat = rounded(r["ZLATITUDE"]), let rlon = rounded(r["ZLONGITUDE"]) {
                meta.set("lat", rlat)
                meta.set("lon", rlon)
            }
            let captionRaw = Py.strip(r["ZLONGDESCRIPTION"].string ?? "")
            let caption: String? = captionRaw.isEmpty ? nil : captionRaw
            let path = kind != "video" ? imagePath(uuid: uuid, directory: r["ZDIRECTORY"].string ?? "", filename: r["ZFILENAME"].string ?? "") : nil
            let title = caption ?? r["ZORIGINALFILENAME"].string
            if try store.upsert(id: Util.stableID("photo", uuid), source: source, kind: kind, ts: ts, title: title,
                                text: caption, meta: meta, path: path) {
                new += 1
            }
            maxAdded = max(maxAdded, r["ZADDEDDATE"].double ?? 0)
        }
        try store.setCursor("photos", maxAdded != 0 ? Py.repr(maxAdded) : cursor, count: new)
        return new
    }
}
