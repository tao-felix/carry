import Foundation

/// Apple Notes (NoteStore.sqlite). Title and snippet come straight from the table; the body is decoded
/// from the gzip+protobuf blob, falling back to the snippet when a note is locked or the format changes.
enum NotesReader: Reader {
    static let db = Readers.home.appendingPathComponent("Library/Group Containers/group.com.apple.notes/NoteStore.sqlite")

    static func available() -> (Bool, String) {
        guard FileManager.default.fileExists(atPath: db.path) else { return (false, "No Notes database") }
        do {
            let con = try SQLiteDB.openReadOnly(db.path)
            defer { con.close() }
            let n = try con.scalar("select count(*) from ZICCLOUDSYNCINGOBJECT where ZTITLE1 is not null and ZMARKEDFORDELETION=0")
            return (true, Readers.countNote(n, "notes"))
        } catch {
            return (false, "Cannot read (\(error)). Grant Full Disk Access.")
        }
    }

    static func collect(store: Store, cfg: JSON, backfillStart: Date, enabled: [String: Bool]) throws -> Int {
        let con = try SQLiteDB.openReadOnly(db.path)
        defer { con.close() }
        let cols = try con.tableColumns("ZICCLOUDSYNCINGOBJECT")
        let createdCol = cols.contains("ZCREATIONDATE1") ? "ZCREATIONDATE1" : (cols.contains("ZCREATIONDATE3") ? "ZCREATIONDATE3" : "ZMODIFICATIONDATE1")
        let lockedCol = cols.contains("ZISPASSWORDPROTECTED") ? "n.ZISPASSWORDPROTECTED" : "0"
        let cursor = try store.getCursor("notes")
        let since = cursor.flatMap { Double($0) } ?? PyTime.dateToApple(backfillStart)
        let rows = try con.query(
            """
            select n.Z_PK, n.ZIDENTIFIER, n.ZTITLE1 as title, n.ZSNIPPET as snippet, n.ZMODIFICATIONDATE1 as modified,
                      n.\(createdCol) as created, \(lockedCol) as locked, d.ZDATA as data, f.ZTITLE2 as folder
               from ZICCLOUDSYNCINGOBJECT n
               left join ZICNOTEDATA d on d.ZNOTE = n.Z_PK
               left join ZICCLOUDSYNCINGOBJECT f on f.Z_PK = n.ZFOLDER
               where n.ZTITLE1 is not null and n.ZMARKEDFORDELETION=0 and n.ZMODIFICATIONDATE1 > ?
               order by n.ZMODIFICATIONDATE1
            """, [.double(since)])
        var new = 0
        var last = since
        for r in rows {
            guard let ts = PyTime.appleToDate(r["modified"]) else { continue }
            let locked = r["locked"].truthy
            let body = locked ? nil : Decoders.noteBody(r["data"].data)
            let snippet = Py.strip(r["snippet"].string ?? "")
            let text = body ?? (snippet.isEmpty ? nil : snippet)
            let created = PyTime.appleToDate(r["created"]) ?? ts
            let meta: JSON = .object([
                ("folder", r["folder"].json),
                ("created", .string(PyTime.iso(created))),
                ("locked", .bool(locked)),
                ("identifier", r["ZIDENTIFIER"].json),
            ])
            let idPart: Any? = (r["ZIDENTIFIER"].string.flatMap { $0.isEmpty ? nil : $0 }) ?? r["Z_PK"]
            if try store.upsert(id: Util.stableID("note", idPart), source: "notes", kind: "note", ts: ts,
                                title: Py.strip(r["title"].string ?? ""), text: text, meta: meta, keepProcessed: false) {
                new += 1
            }
            last = max(last, r["modified"].double ?? 0)
        }
        try store.setCursor("notes", Py.repr(last), count: new)
        return new
    }
}
