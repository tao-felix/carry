import Foundation
import SQLite3

/// One SQLite value with its storage class kept, so `str()` of an INTEGER and a REAL differ exactly as in Python.
enum SQLValue {
    case null
    case int(Int64)
    case double(Double)
    case text(String)
    case blob(Data)

    var isNull: Bool { if case .null = self { return true }; return false }
    var int: Int64? {
        switch self {
        case .int(let i): return i
        case .double(let d): return Int64(exactly: d)
        case .text(let s): return Int64(s)
        default: return nil
        }
    }
    var double: Double? {
        switch self {
        case .int(let i): return Double(i)
        case .double(let d): return d
        case .text(let s): return Double(s)
        default: return nil
        }
    }
    var string: String? {
        switch self {
        case .text(let s): return s
        case .int(let i): return String(i)
        case .double(let d): return Py.repr(d)
        default: return nil
        }
    }
    var data: Data? { if case .blob(let d) = self { return d }; return nil }
    /// Python truthiness of the sqlite3 value.
    var truthy: Bool {
        switch self {
        case .null: return false
        case .int(let i): return i != 0
        case .double(let d): return d != 0
        case .text(let s): return !s.isEmpty
        case .blob(let d): return !d.isEmpty
        }
    }
    /// `str(value)`
    var pyStr: String {
        switch self {
        case .null: return "None"
        case .int(let i): return String(i)
        case .double(let d): return Py.repr(d)
        case .text(let s): return s
        case .blob(let d): return "b'\(d.count) bytes'"
        }
    }
    var json: JSON {
        switch self {
        case .null: return .null
        case .int(let i): return .int(i)
        case .double(let d): return .double(d)
        case .text(let s): return .string(s)
        case .blob: return .null
        }
    }
}

struct SQLiteError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

/// A row as `name → value`.
struct SQLRow {
    let columns: [String]
    let values: [SQLValue]

    subscript(_ name: String) -> SQLValue {
        guard let i = columns.firstIndex(of: name) else { return .null }
        return values[i]
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// A thin wrapper around the system libsqlite3 (FTS5 with the trigram tokenizer is compiled in).
final class SQLiteDB {
    private(set) var handle: OpaquePointer?
    let path: String

    /// `open_ro`: a live Apple database, read-only, never copied. Fails like Python's `sqlite3.connect`
    /// with "unable to open database file" when Full Disk Access is missing.
    static func openReadOnly(_ path: String) throws -> SQLiteDB {
        guard FileManager.default.fileExists(atPath: path) else {
            throw SQLiteError(message: "[Errno 2] No such file or directory: '\(path)'")
        }
        return try SQLiteDB(path: path, flags: SQLITE_OPEN_READONLY, busyTimeoutMs: 5_000)
    }

    static func openReadWrite(_ path: String) throws -> SQLiteDB {
        try SQLiteDB(path: path, flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, busyTimeoutMs: 30_000)
    }

    private init(path: String, flags: Int32, busyTimeoutMs: Int32) throws {
        self.path = path
        var db: OpaquePointer?
        let rc = sqlite3_open_v2(path, &db, flags, nil)
        if rc != SQLITE_OK {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unable to open database file"
            if let db { sqlite3_close(db) }
            throw SQLiteError(message: message)
        }
        handle = db
        sqlite3_busy_timeout(db, busyTimeoutMs)
    }

    deinit { close() }

    func close() {
        if let handle { sqlite3_close(handle) }
        handle = nil
    }

    private func errorMessage() -> String {
        handle.map { String(cString: sqlite3_errmsg($0)) } ?? "closed"
    }

    /// Run one or more statements without results (schema, pragmas).
    func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(handle, sql, nil, nil, &err) != SQLITE_OK {
            let message = err.map { String(cString: $0) } ?? errorMessage()
            sqlite3_free(err)
            throw SQLiteError(message: message)
        }
    }

    /// Execute a statement with bound parameters, returning all rows.
    @discardableResult
    func query(_ sql: String, _ args: [SQLValue] = []) throws -> [SQLRow] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw SQLiteError(message: errorMessage())
        }
        defer { sqlite3_finalize(stmt) }
        for (i, arg) in args.enumerated() {
            let idx = Int32(i + 1)
            switch arg {
            case .null: sqlite3_bind_null(stmt, idx)
            case .int(let v): sqlite3_bind_int64(stmt, idx, v)
            case .double(let v): sqlite3_bind_double(stmt, idx, v)
            case .text(let s): sqlite3_bind_text(stmt, idx, s, -1, SQLITE_TRANSIENT)
            case .blob(let d):
                d.withUnsafeBytes { buf in _ = sqlite3_bind_blob(stmt, idx, buf.baseAddress, Int32(d.count), SQLITE_TRANSIENT) }
            }
        }
        let count = Int(sqlite3_column_count(stmt))
        let columns = (0 ..< count).map { String(cString: sqlite3_column_name(stmt, Int32($0))) }
        var rows: [SQLRow] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_ROW {
                var values: [SQLValue] = []
                values.reserveCapacity(count)
                for c in 0 ..< count {
                    let col = Int32(c)
                    switch sqlite3_column_type(stmt, col) {
                    case SQLITE_INTEGER: values.append(.int(sqlite3_column_int64(stmt, col)))
                    case SQLITE_FLOAT: values.append(.double(sqlite3_column_double(stmt, col)))
                    case SQLITE_TEXT:
                        if let p = sqlite3_column_text(stmt, col) { values.append(.text(String(cString: p))) } else { values.append(.null) }
                    case SQLITE_BLOB:
                        let n = Int(sqlite3_column_bytes(stmt, col))
                        if let p = sqlite3_column_blob(stmt, col), n > 0 { values.append(.blob(Data(bytes: p, count: n))) } else { values.append(.blob(Data())) }
                    default: values.append(.null)
                    }
                }
                rows.append(SQLRow(columns: columns, values: values))
            } else if rc == SQLITE_DONE {
                break
            } else {
                throw SQLiteError(message: errorMessage())
            }
        }
        return rows
    }

    func scalar(_ sql: String, _ args: [SQLValue] = []) throws -> SQLValue {
        try query(sql, args).first?.values.first ?? .null
    }

    /// `table_columns`
    func tableColumns(_ table: String) throws -> Set<String> {
        Set(try query("pragma table_info('\(table)')").compactMap { $0["name"].string })
    }

    /// `has_table`
    func hasTable(_ table: String) throws -> Bool {
        !(try query("select 1 from sqlite_master where name=?", [.text(table)])).isEmpty
    }
}

extension SQLValue {
    init(_ s: String?) { self = s.map { .text($0) } ?? .null }
    init(_ d: Double?) { self = d.map { .double($0) } ?? .null }
    init(_ i: Int?) { self = i.map { .int(Int64($0)) } ?? .null }
}
