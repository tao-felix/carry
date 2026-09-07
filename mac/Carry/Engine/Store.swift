import Foundation

/// One row of `items`, as Python's sqlite3.Row hands it to digest.py and mcp_server.py.
struct Item {
    let id: String
    let source: String
    let kind: String
    let ts: String
    let tsEnd: String?
    let day: String
    let title: String?
    let text: String?
    let metaText: String?
    let path: String?
    let device: String?
    let processed: Bool
    let createdAt: String?
    let updatedAt: String?

    /// `_m(row)`: `json.loads(row["meta"] or "{}")`
    let meta: JSON

    init(_ row: SQLRow) {
        id = row["id"].string ?? ""
        source = row["source"].string ?? ""
        kind = row["kind"].string ?? ""
        ts = row["ts"].string ?? ""
        tsEnd = row["ts_end"].string
        day = row["day"].string ?? ""
        title = row["title"].string
        text = row["text"].string
        metaText = row["meta"].string
        path = row["path"].string
        device = row["device"].string
        processed = row["processed"].truthy
        createdAt = row["created_at"].string
        updatedAt = row["updated_at"].string
        let parsed = metaText.flatMap { $0.isEmpty ? nil : JSON.parse($0) }
        meta = parsed ?? .object([])
    }

    /// `row["title"] or ""`
    var titleOrEmpty: String { title ?? "" }
    /// `row["text"] or ""`
    var textOrEmpty: String { text ?? "" }

    /// `_row(r)` in mcp_server.py.
    var mcpJSON: JSON {
        .object([("id", .string(id)), ("source", .string(source)), ("kind", .string(kind)), ("ts", .string(ts)),
                 ("ts_end", .str(tsEnd)), ("title", .str(title)), ("text", .str(text)), ("meta", meta)])
    }
}

struct SyncState {
    let source: String
    let cursor: String?
    let lastRun: String?
    let lastCount: Int
    let lastError: String?
}

/// `~/.carry/carry.db`: one SQLite store for everything, FTS5 trigram (so Chinese works), per-source cursors.
/// Schema, triggers and every query are those of cli/src/carry/store.py.
final class Store {
    static let schema = """
    create table if not exists items (
      id text primary key,
      source text not null,
      kind text not null,
      ts text not null,
      ts_end text,
      day text not null,
      title text,
      text text,
      meta text,
      path text,
      device text,
      processed integer default 0,
      created_at text,
      updated_at text
    );
    create index if not exists items_day on items(day, source);
    create index if not exists items_source_ts on items(source, ts);
    create virtual table if not exists items_fts using fts5(title, text, content='items', content_rowid='rowid', tokenize='trigram');
    create trigger if not exists items_ai after insert on items begin
      insert into items_fts(rowid, title, text) values (new.rowid, new.title, new.text);
    end;
    create trigger if not exists items_ad after delete on items begin
      insert into items_fts(items_fts, rowid, title, text) values('delete', old.rowid, old.title, old.text);
    end;
    create trigger if not exists items_au after update on items begin
      insert into items_fts(items_fts, rowid, title, text) values('delete', old.rowid, old.title, old.text);
      insert into items_fts(rowid, title, text) values (new.rowid, new.title, new.text);
    end;
    create table if not exists sync_state (
      source text primary key,
      cursor text,
      last_run text,
      last_count integer default 0,
      last_error text
    );
    """

    let db: SQLiteDB
    private var inTransaction = false

    init(path: URL = CarryPaths.db) throws {
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        db = try SQLiteDB.openReadWrite(path.path)
        try db.exec("pragma journal_mode=wal")
        try db.exec(Self.schema)
    }

    // Python's sqlite3 module opens a transaction before the first write and commits on `commit()`.
    private func beginIfNeeded() throws {
        if !inTransaction { try db.exec("begin"); inTransaction = true }
    }

    func commit() {
        guard inTransaction else { return }
        try? db.exec("commit")
        inTransaction = false
    }

    func close() {
        commit()
        db.close()
    }

    // MARK: - items

    /// Insert or update. Returns true when the row is new. A re-read never overwrites the text of a row
    /// that processing (OCR / transcript) produced unless `keepProcessed` is false.
    @discardableResult
    func upsert(id: String, source: String, kind: String, ts: Date, tsEnd: Date? = nil, title: String? = nil,
                text: String? = nil, meta: JSON = .object([]), path: String? = nil, device: String? = nil,
                keepProcessed: Bool = true) throws -> Bool {
        try beginIfNeeded()
        let t = PyTime.iso(ts)
        let stamp = PyTime.iso(PyTime.now())
        let metaText = meta.dumps()
        let existing = try db.query("select processed, text from items where id=?", [.text(id)]).first
        guard let existing else {
            try db.query(
                "insert into items(id,source,kind,ts,ts_end,day,title,text,meta,path,device,processed,created_at,updated_at)"
                    + " values(?,?,?,?,?,?,?,?,?,?,?,0,?,?)",
                [.text(id), .text(source), .text(kind), .text(t), SQLValue(PyTime.iso(tsEnd)), .text(PyTime.day(of: ts)),
                 SQLValue(title), SQLValue(text), .text(metaText), SQLValue(path), SQLValue(device), .text(stamp), .text(stamp)])
            return true
        }
        let newText: String?
        if keepProcessed, existing["processed"].truthy {
            newText = existing["text"].string
        } else if let text, !text.isEmpty {
            newText = text
        } else if !keepProcessed {
            newText = text
        } else {
            newText = existing["text"].string
        }
        try db.query(
            "update items set source=?,kind=?,ts=?,ts_end=?,day=?,title=?,text=?,meta=?,path=?,device=?,updated_at=? where id=?",
            [.text(source), .text(kind), .text(t), SQLValue(PyTime.iso(tsEnd)), .text(PyTime.day(of: ts)), SQLValue(title),
             SQLValue(newText), .text(metaText), SQLValue(path), SQLValue(device), .text(stamp), .text(id)])
        return false
    }

    func setProcessed(id: String, text: String?, extraMeta: JSON = .object([])) throws {
        try beginIfNeeded()
        let row = try db.query("select meta from items where id=?", [.text(id)]).first
        var meta = row.flatMap { r -> JSON? in
            guard let m = r["meta"].string, !m.isEmpty else { return nil }
            return JSON.parse(m)
        } ?? .object([])
        meta.update(extraMeta)
        try db.query("update items set text=?, processed=1, meta=?, updated_at=? where id=?",
                     [SQLValue(text), .text(meta.dumps()), .text(PyTime.iso(PyTime.now())), .text(id)])
    }

    func pending(_ source: String, limit: Int = 200) throws -> [Item] {
        try db.query("select * from items where source=? and processed=0 and path is not null order by ts desc limit ?",
                     [.text(source), .int(Int64(limit))]).map(Item.init)
    }

    func dayItems(_ day: String, source: String? = nil) throws -> [Item] {
        if let source {
            return try db.query("select * from items where day=? and source=? order by ts", [.text(day), .text(source)]).map(Item.init)
        }
        return try db.query("select * from items where day=? order by source, ts", [.text(day)]).map(Item.init)
    }

    func between(_ source: String, _ start: Date, _ end: Date, kind: String? = nil) throws -> [Item] {
        var sql = "select * from items where source=? and ts>=? and ts<?"
        var args: [SQLValue] = [.text(source), .text(PyTime.iso(start)), .text(PyTime.iso(end))]
        if let kind {
            sql += " and kind=?"
            args.append(.text(kind))
        }
        return try db.query(sql + " order by ts", args).map(Item.init)
    }

    func endingBetween(_ source: String, kind: String, _ start: Date, _ end: Date) throws -> [Item] {
        try db.query("select * from items where source=? and kind=? and ts_end>=? and ts_end<? order by ts",
                     [.text(source), .text(kind), .text(PyTime.iso(start)), .text(PyTime.iso(end))]).map(Item.init)
    }

    func recent(_ source: String, limit: Int = 20) throws -> [Item] {
        try db.query("select * from items where source=? order by ts desc limit ?", [.text(source), .int(Int64(limit))]).map(Item.init)
    }

    func get(_ id: String) throws -> Item? {
        try db.query("select * from items where id=?", [.text(id)]).first.map(Item.init)
    }

    /// FTS `MATCH` (phrase) for three or more characters, `LIKE` otherwise.
    func search(_ query: String, source: String? = nil, since: String? = nil, limit: Int = 20) throws -> [Item] {
        let q = Py.strip(query)
        if q.isEmpty { return [] }
        var sql: String
        var args: [SQLValue] = []
        if Py.len(q) >= 3 {
            sql = "select i.*, bm25(items_fts) as rank from items_fts join items i on i.rowid=items_fts.rowid where items_fts match ?"
            args.append(.text("\"" + q.replacingOccurrences(of: "\"", with: "\"\"") + "\""))
        } else {
            sql = "select i.*, 0 as rank from items i where (i.title like ? or i.text like ?)"
            args += [.text("%\(q)%"), .text("%\(q)%")]
        }
        if let source {
            sql += " and i.source=?"
            args.append(.text(source))
        }
        if let since {
            sql += " and i.ts>=?"
            args.append(.text(since))
        }
        sql += " order by rank, i.ts desc limit ?"
        args.append(.int(Int64(limit)))
        return try db.query(sql, args).map(Item.init)
    }

    func counts() throws -> [String: Int] {
        var out: [String: Int] = [:]
        for r in try db.query("select source, count(*) n from items group by source") {
            out[r["source"].string ?? ""] = Int(r["n"].int ?? 0)
        }
        return out
    }

    func dayCounts(_ day: String) throws -> [String: Int] {
        var out: [String: Int] = [:]
        for r in try db.query("select source, count(*) n from items where day=? group by source", [.text(day)]) {
            out[r["source"].string ?? ""] = Int(r["n"].int ?? 0)
        }
        return out
    }

    func daysWithData(limit: Int = 14) throws -> [String] {
        try db.query("select distinct day from items order by day desc limit ?", [.int(Int64(limit))]).compactMap { $0["day"].string }
    }

    /// digest.py reads reminders with a raw query; keep it verbatim.
    func allReminders() throws -> [Item] {
        try db.query("select * from items where source='reminders' order by ts").map(Item.init)
    }

    // MARK: - cursors

    func getCursor(_ source: String) throws -> String? {
        try db.query("select cursor from sync_state where source=?", [.text(source)]).first?["cursor"].string
    }

    func setCursor(_ source: String, _ cursor: String?, count: Int, error: String? = nil) throws {
        try beginIfNeeded()
        try db.query(
            "insert into sync_state(source,cursor,last_run,last_count,last_error) values(?,?,?,?,?)"
                + " on conflict(source) do update set cursor=coalesce(excluded.cursor, sync_state.cursor), last_run=excluded.last_run,"
                + " last_count=excluded.last_count, last_error=excluded.last_error",
            [.text(source), SQLValue(cursor), .text(PyTime.iso(PyTime.now())), .int(Int64(count)), SQLValue(error)])
    }

    func clearCursor(_ source: String) throws {
        try beginIfNeeded()
        try db.query("update sync_state set cursor=NULL where source=?", [.text(source)])
    }

    /// In rowid order, like Python's dict built from `select * from sync_state`.
    func syncStates() throws -> [SyncState] {
        try db.query("select * from sync_state").map {
            SyncState(source: $0["source"].string ?? "", cursor: $0["cursor"].string, lastRun: $0["last_run"].string,
                      lastCount: Int($0["last_count"].int ?? 0), lastError: $0["last_error"].string)
        }
    }
}
