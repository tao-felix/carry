import Foundation

/// Voice Memos synced by iCloud (CloudRecordings.db + the audio files next to it).
enum VoiceMemosReader: Reader {
    static let dir = Readers.home.appendingPathComponent("Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings", isDirectory: true)
    static let db = dir.appendingPathComponent("CloudRecordings.db")

    static func available() -> (Bool, String) {
        guard FileManager.default.fileExists(atPath: db.path) else { return (false, "No Voice Memos database") }
        do {
            let con = try SQLiteDB.openReadOnly(db.path)
            defer { con.close() }
            return (true, Readers.countNote(try con.scalar("select count(*) from ZCLOUDRECORDING"), "recordings"))
        } catch {
            return (false, "Cannot read (\(error)). Grant Full Disk Access.")
        }
    }

    static func collect(store: Store, cfg: JSON, backfillStart: Date, enabled: [String: Bool]) throws -> Int {
        let con = try SQLiteDB.openReadOnly(db.path)
        defer { con.close() }
        let cols = try con.tableColumns("ZCLOUDRECORDING")
        let titleCol = cols.contains("ZENCRYPTEDTITLE") ? "ZENCRYPTEDTITLE" : (cols.contains("ZCUSTOMLABEL") ? "ZCUSTOMLABEL" : "ZPATH")
        let cursor = try store.getCursor("voice_memos")
        let since = cursor.flatMap { Double($0) } ?? PyTime.dateToApple(backfillStart)
        let rows = try con.query(
            "select Z_PK, \(titleCol) as title, ZPATH, ZDURATION, ZDATE from ZCLOUDRECORDING where ZDATE > ? order by ZDATE",
            [.double(since)])
        var new = 0
        var last = since
        for r in rows {
            guard let ts = PyTime.appleToDate(r["ZDATE"]), let zpath = r["ZPATH"].string, !zpath.isEmpty else { continue }
            let path = dir.appendingPathComponent(zpath)
            // `round(r["ZDURATION"] or 0, 1)`: an INTEGER column stays an int, a REAL one a float, NULL → 0.
            let duration: JSON
            switch r["ZDURATION"] {
            case .double(let d): duration = d == 0 ? .int(0) : .double(Py.round(d, 1))
            case .int(let i): duration = .int(i)
            default: duration = .int(0)
            }
            let meta: JSON = .object([("duration_s", duration), ("file", .string(zpath))])
            let title = Py.strip((r["title"].string.flatMap { $0.isEmpty ? nil : $0 }) ?? zpath)
            if try store.upsert(id: Util.stableID("memo", zpath), source: "voice_memos", kind: "voice_memo", ts: ts, title: title,
                                meta: meta, path: FileManager.default.fileExists(atPath: path.path) ? path.path : nil) {
                new += 1
            }
            last = max(last, r["ZDATE"].double ?? 0)
        }
        try store.setCursor("voice_memos", Py.repr(last), count: new)
        return new
    }
}
