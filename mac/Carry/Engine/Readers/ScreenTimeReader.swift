import Foundation

/// App usage from knowledgeC.db (/app/usage). This Mac always; the iPhone too when Screen Time's
/// "Share Across Devices" is on (then rows carry a device id).
enum ScreenTimeReader: Reader {
    static let db = Readers.home.appendingPathComponent("Library/Application Support/Knowledge/knowledgeC.db")

    static func available() -> (Bool, String) {
        guard FileManager.default.fileExists(atPath: db.path) else { return (false, "No knowledgeC.db") }
        do {
            let con = try SQLiteDB.openReadOnly(db.path)
            defer { con.close() }
            return (true, Readers.countNote(try con.scalar("select count(*) from ZOBJECT where ZSTREAMNAME='/app/usage'"), "usage rows"))
        } catch {
            return (false, "Cannot read (\(error)). Grant Full Disk Access.")
        }
    }

    static func collect(store: Store, cfg: JSON, backfillStart: Date, enabled: [String: Bool]) throws -> Int {
        let con = try SQLiteDB.openReadOnly(db.path)
        defer { con.close() }
        // Recompute the last two days every run; older days are stable.
        let today = PyTime.dayBounds(PyTime.day(of: PyTime.now()))!.start
        var start = max(backfillStart, today.addingTimeInterval(-86_400))
        if try store.getCursor("screen_time") == nil { start = backfillStart }
        let rows = try con.query(
            """
            select o.ZSTARTDATE, o.ZENDDATE, o.ZVALUESTRING as bundle, s.ZDEVICEID as device
               from ZOBJECT o left join ZSOURCE s on o.ZSOURCE = s.Z_PK
               where o.ZSTREAMNAME='/app/usage' and o.ZSTARTDATE >= ? and o.ZENDDATE > o.ZSTARTDATE
            """, [.double(PyTime.dateToApple(start))])
        var order: [(String, String, String)] = []
        var minutes: [String: Double] = [:]
        for r in rows {
            guard let s = PyTime.appleToDate(r["ZSTARTDATE"]), let bundle = r["bundle"].string, !bundle.isEmpty else { continue }
            let device = r["device"].truthy ? "iphone" : "mac"
            let key = (PyTime.day(of: s), bundle, device)
            let k = "\(key.0)|\(key.1)|\(key.2)"
            if minutes[k] == nil { order.append(key); minutes[k] = 0 }
            minutes[k]! += ((r["ZENDDATE"].double ?? 0) - (r["ZSTARTDATE"].double ?? 0)) / 60
        }
        var new = 0
        for (day, bundle, device) in order {
            let mins = minutes["\(day)|\(bundle)|\(device)"] ?? 0
            if mins < 1 { continue }
            guard let ts = PyTime.dayBounds(day)?.start else { continue }
            let meta: JSON = .object([("bundle", .string(bundle)), ("minutes", .num(Py.roundInt(mins))), ("device", .string(device))])
            if try store.upsert(id: Util.stableID("usage", day, bundle, device), source: "screen_time", kind: "app_usage", ts: ts,
                                title: Apps.name(bundle), meta: meta, device: device) {
                new += 1
            }
        }
        try store.setCursor("screen_time", "1", count: new)
        return new
    }
}
