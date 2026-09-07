import Foundation

/// Safari history (iCloud-synced across devices). Off by default.
enum SafariReader: Reader {
    static let db = Readers.home.appendingPathComponent("Library/Safari/History.db")

    static func available() -> (Bool, String) {
        guard FileManager.default.fileExists(atPath: db.path) else { return (false, "No Safari history") }
        do {
            let con = try SQLiteDB.openReadOnly(db.path)
            defer { con.close() }
            return (true, Readers.countNote(try con.scalar("select count(*) from history_visits"), "visits"))
        } catch {
            return (false, "Cannot read (\(error)). Grant Full Disk Access.")
        }
    }

    /// `urlsplit(url).netloc`
    static func netloc(_ url: String) -> String {
        guard let schemeEnd = url.range(of: "://") else { return "" }
        let rest = url[schemeEnd.upperBound...]
        let end = rest.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) ?? rest.endIndex
        return String(rest[..<end])
    }

    static func collect(store: Store, cfg: JSON, backfillStart: Date, enabled: [String: Bool]) throws -> Int {
        let con = try SQLiteDB.openReadOnly(db.path)
        defer { con.close() }
        let cursor = try store.getCursor("safari")
        let since = cursor.flatMap { Double($0) } ?? PyTime.dateToApple(backfillStart)
        let rows = try con.query(
            """
            select v.id, v.visit_time, v.title, i.url from history_visits v join history_items i on i.id = v.history_item
               where v.visit_time > ? order by v.visit_time
            """, [.double(since)])
        var new = 0
        var last = since
        for r in rows {
            guard let ts = PyTime.appleToDate(r["visit_time"]), let url = r["url"].string, !url.isEmpty else { continue }
            let host = netloc(url)
            let title = Py.strip((r["title"].string.flatMap { $0.isEmpty ? nil : $0 }) ?? (host.isEmpty ? url : host))
            if try store.upsert(id: Util.stableID("safari", r["id"]), source: "safari", kind: "visit", ts: ts, title: title,
                                text: url, meta: .object([("host", .string(host))])) {
                new += 1
            }
            last = max(last, r["visit_time"].double ?? 0)
        }
        try store.setCursor("safari", Py.repr(last), count: new)
        return new
    }
}
