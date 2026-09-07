import Foundation

/// Reminders from the app-group stores (one SQLite per account).
enum RemindersReader: Reader {
    static let storesDir = Readers.home.appendingPathComponent("Library/Group Containers/group.com.apple.reminders/Container_v1/Stores", isDirectory: true)

    static func files() -> [URL] { Readers.glob(storesDir, prefix: "Data-", suffix: ".sqlite") }

    static func available() -> (Bool, String) {
        let stores = files()
        guard !stores.isEmpty else { return (false, "No Reminders stores visible. Grant Full Disk Access.") }
        var total = 0
        do {
            for f in stores {
                let con = try SQLiteDB.openReadOnly(f.path)
                defer { con.close() }
                total += Int(try con.scalar("select count(*) from ZREMCDREMINDER where ZMARKEDFORDELETION=0").int ?? 0)
            }
            return (true, "\(Py.thousands(total)) reminders")
        } catch {
            return (false, "Cannot read (\(error)). Grant Full Disk Access.")
        }
    }

    static func collect(store: Store, cfg: JSON, backfillStart: Date, enabled: [String: Bool]) throws -> Int {
        let since = PyTime.dateToApple(backfillStart)
        var new = 0
        for f in files() {
            let con = try SQLiteDB.openReadOnly(f.path)
            defer { con.close() }
            let cols = try con.tableColumns("ZREMCDREMINDER")
            var lists: [Int64: SQLValue] = [:]
            if try con.hasTable("ZREMCDBASELIST"), try con.tableColumns("ZREMCDBASELIST").contains("ZNAME") {
                for r in try con.query("select Z_PK, ZNAME from ZREMCDBASELIST") {
                    if let pk = r["Z_PK"].int { lists[pk] = r["ZNAME"] }
                }
            }
            let notesCol = cols.contains("ZNOTES") ? "ZNOTES" : "null"
            let rows = try con.query(
                """
                select Z_PK, ZTITLE, ZDUEDATE, ZCOMPLETED, ZCOMPLETIONDATE, ZCREATIONDATE, ZLASTMODIFIEDDATE, ZLIST,
                          \(notesCol) as notes, ZFLAGGED
                   from ZREMCDREMINDER where ZMARKEDFORDELETION=0 and ZTITLE is not null
                     and (ZLASTMODIFIEDDATE > ? or ZDUEDATE > ? or ZCOMPLETED = 0)
                """, [.double(since), .double(since)])
            for r in rows {
                let due = PyTime.appleToDate(r["ZDUEDATE"])
                let done = r["ZCOMPLETED"].truthy ? PyTime.appleToDate(r["ZCOMPLETIONDATE"]) : nil
                let created = PyTime.appleToDate(r["ZCREATIONDATE"])
                guard let ts = done ?? due ?? created else { continue }
                let listName: JSON = r["ZLIST"].int.flatMap { lists[$0] }.map { $0.json } ?? .string("")
                let meta: JSON = .object([
                    ("list", listName), ("completed", .bool(r["ZCOMPLETED"].truthy)),
                    ("due", .str(PyTime.iso(due))), ("completed_at", .str(PyTime.iso(done))),
                    ("flagged", .bool(r["ZFLAGGED"].truthy)), ("created", .str(PyTime.iso(created))),
                ])
                let notes = Py.strip(r["notes"].string ?? "")
                if try store.upsert(id: Util.stableID("rem", f.lastPathComponent, r["Z_PK"]), source: "reminders", kind: "reminder", ts: ts,
                                    title: Py.strip(r["ZTITLE"].string ?? ""), text: notes.isEmpty ? nil : notes, meta: meta) {
                    new += 1
                }
            }
        }
        try store.setCursor("reminders", nil, count: new)
        return new
    }
}
