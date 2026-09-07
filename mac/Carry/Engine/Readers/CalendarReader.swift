import Foundation

/// Calendar events from the shared Calendar.sqlitedb. Uses the occurrence cache so repeating events show up.
enum CalendarReader: Reader {
    static let db = Readers.home.appendingPathComponent("Library/Group Containers/group.com.apple.calendar/Calendar.sqlitedb")
    static let legacy = Readers.home.appendingPathComponent("Library/Calendars/Calendar.sqlitedb")
    static let lookaheadDays = 14

    static var file: URL { FileManager.default.fileExists(atPath: db.path) ? db : legacy }

    static func available() -> (Bool, String) {
        let p = file
        guard FileManager.default.fileExists(atPath: p.path) else { return (false, "No Calendar database") }
        do {
            let con = try SQLiteDB.openReadOnly(p.path)
            defer { con.close() }
            return (true, Readers.countNote(try con.scalar("select count(*) from CalendarItem"), "items"))
        } catch {
            return (false, "Cannot read (\(error)). Grant Full Disk Access.")
        }
    }

    static func collect(store: Store, cfg: JSON, backfillStart: Date, enabled: [String: Bool]) throws -> Int {
        let con = try SQLiteDB.openReadOnly(file.path)
        defer { con.close() }
        var cals: [Int64: SQLValue] = [:]
        for r in try con.query("select ROWID, title from Calendar") {
            if let id = r["ROWID"].int { cals[id] = r["title"] }
        }
        let start = PyTime.dateToApple(backfillStart)
        let end = PyTime.dateToApple(PyTime.now().addingTimeInterval(Double(lookaheadDays) * 86_400))
        let rows: [SQLRow]
        if try con.hasTable("OccurrenceCache") {
            rows = try con.query(
                """
                select oc.occurrence_date as s, oc.occurrence_end_date as e, ci.ROWID as id, ci.summary, ci.all_day,
                          ci.calendar_id, ci.description, ci.status
                   from OccurrenceCache oc join CalendarItem ci on ci.ROWID = oc.event_id
                   where oc.occurrence_date >= ? and oc.occurrence_date < ? order by oc.occurrence_date
                """, [.double(start), .double(end)])
        } else {
            rows = try con.query(
                """
                select ci.start_date as s, ci.end_date as e, ci.ROWID as id, ci.summary, ci.all_day, ci.calendar_id,
                          ci.description, ci.status
                   from CalendarItem ci where ci.start_date >= ? and ci.start_date < ? order by ci.start_date
                """, [.double(start), .double(end)])
        }
        var new = 0
        for r in rows {
            guard let ts = PyTime.appleToDate(r["s"]), let summary = r["summary"].string, !summary.isEmpty else { continue }
            if r["status"].int == 3 { continue } // cancelled
            let calendarTitle: JSON = r["calendar_id"].int.flatMap { cals[$0] }.map { $0.json } ?? .string("")
            let notesRaw = Py.prefix(Py.strip(r["description"].string ?? ""), 500)
            let notes: JSON = notesRaw.isEmpty ? .null : .string(notesRaw)
            let meta: JSON = .object([("calendar", calendarTitle), ("all_day", .bool(r["all_day"].truthy)), ("notes", notes)])
            if try store.upsert(id: Util.stableID("cal", r["id"], r["s"]), source: "calendar", kind: "event", ts: ts,
                                tsEnd: PyTime.appleToDate(r["e"]), title: Py.strip(summary), text: notes.string, meta: meta) {
                new += 1
            }
        }
        try store.setCursor("calendar", nil, count: new)
        return new
    }
}
