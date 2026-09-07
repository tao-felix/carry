import CryptoKit
import Foundation

// The helpers of cli/src/carry/util.py, with Python's exact string semantics where the output
// reaches carry.db or a digest: ids, RFC 3339 stamps, whitespace, excerpts, float repr.

// MARK: - Python string semantics

enum Py {
    /// `str.isspace()`: Unicode Zs plus the bidi-B/S controls Python counts as whitespace.
    static func isSpace(_ s: Unicode.Scalar) -> Bool {
        switch s.value {
        case 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x1C, 0x1D, 0x1E, 0x1F, 0x20, 0x85, 0x2028, 0x2029: return true
        default: return s.properties.generalCategory == .spaceSeparator
        }
    }

    /// `str.strip()`
    static func strip(_ s: String) -> String {
        let scalars = Array(s.unicodeScalars)
        var lo = 0, hi = scalars.count
        while lo < hi, isSpace(scalars[lo]) { lo += 1 }
        while hi > lo, isSpace(scalars[hi - 1]) { hi -= 1 }
        return String(String.UnicodeScalarView(scalars[lo ..< hi]))
    }

    /// `str.rstrip()`
    static func rstrip(_ s: String) -> String {
        let scalars = Array(s.unicodeScalars)
        var hi = scalars.count
        while hi > 0, isSpace(scalars[hi - 1]) { hi -= 1 }
        return String(String.UnicodeScalarView(scalars[0 ..< hi]))
    }

    /// `str.split()` with no separator: runs of whitespace, no empty parts.
    static func split(_ s: String) -> [String] {
        var out: [String] = []
        var current = String.UnicodeScalarView()
        for scalar in s.unicodeScalars {
            if isSpace(scalar) {
                if !current.isEmpty { out.append(String(current)); current = String.UnicodeScalarView() }
            } else {
                current.append(scalar)
            }
        }
        if !current.isEmpty { out.append(String(current)) }
        return out
    }

    /// `str.splitlines()`
    static func splitlines(_ s: String) -> [String] {
        var out: [String] = []
        var current = String.UnicodeScalarView()
        var scalars = s.unicodeScalars.makeIterator()
        var pending: Unicode.Scalar? = nil
        while true {
            let scalar: Unicode.Scalar
            if let p = pending { scalar = p; pending = nil } else if let n = scalars.next() { scalar = n } else { break }
            switch scalar.value {
            case 0x0D:
                out.append(String(current)); current = String.UnicodeScalarView()
                if let n = scalars.next() { if n.value != 0x0A { pending = n } }
            case 0x0A, 0x0B, 0x0C, 0x1C, 0x1D, 0x1E, 0x85, 0x2028, 0x2029:
                out.append(String(current)); current = String.UnicodeScalarView()
            default:
                current.append(scalar)
            }
        }
        if !current.isEmpty { out.append(String(current)) }
        return out
    }

    /// `len(s)`: code points.
    static func len(_ s: String) -> Int { s.unicodeScalars.count }

    /// `s[:n]` in code points.
    static func prefix(_ s: String, _ n: Int) -> String {
        String(String.UnicodeScalarView(s.unicodeScalars.prefix(max(0, n))))
    }

    /// `s[n:]` in code points.
    static func dropFirst(_ s: String, _ n: Int) -> String {
        String(String.UnicodeScalarView(s.unicodeScalars.dropFirst(max(0, n))))
    }

    /// `str.capitalize()`
    static func capitalize(_ s: String) -> String {
        guard let first = s.unicodeScalars.first else { return s }
        return String(first).uppercased() + dropFirst(s, 1).lowercased()
    }

    /// `str.isdigit()` for the characters that reach us (phone handles).
    static func isDigit(_ s: String) -> Bool {
        !s.isEmpty && s.unicodeScalars.allSatisfy { $0.properties.numericType == .decimal || $0.properties.numericType == .digit }
    }

    /// `f"{n:,}"`
    static func thousands(_ n: Int) -> String {
        let digits = String(abs(n))
        var out = ""
        for (i, ch) in digits.reversed().enumerated() {
            if i > 0, i % 3 == 0 { out.append(",") }
            out.append(ch)
        }
        return (n < 0 ? "-" : "") + String(out.reversed())
    }

    /// `round(x, ndigits)` for floats: correctly rounded, like CPython's dtoa path.
    static func round(_ x: Double, _ ndigits: Int) -> Double {
        Double(String(format: "%.\(ndigits)f", x)) ?? x
    }

    /// `round(x)` → int, half to even.
    static func roundInt(_ x: Double) -> Int { Int(x.rounded(.toNearestOrEven)) }

    /// `f"{x:.nf}"`
    static func fixed(_ x: Double, _ n: Int) -> String { String(format: "%.\(n)f", x) }

    /// `str(x)` for a float: shortest repr (Swift's description agrees with CPython's repr).
    static func repr(_ x: Double) -> String {
        if x.isNaN { return "nan" }
        if x.isInfinite { return x < 0 ? "-inf" : "inf" }
        return x.description
    }

    /// `str(value)` for the scalar kinds that flow into ids and texts.
    static func str(_ v: Any?) -> String {
        guard let v else { return "None" }
        switch v {
        case let s as String: return s
        case let i as Int: return String(i)
        case let i as Int64: return String(i)
        case let d as Double: return repr(d)
        case let b as Bool: return b ? "True" : "False"
        case let j as JSON: return j.pyStr
        case let q as SQLValue: return q.pyStr
        default: return String(describing: v)
        }
    }
}

// MARK: - Time (util.py)

enum PyTime {
    static let appleEpoch: Double = 978_307_200

    /// Python: `LOCAL_TZ = datetime.now().astimezone().tzinfo`, a fixed offset captured once.
    static let localTZ: TimeZone = TimeZone(secondsFromGMT: TimeZone.current.secondsFromGMT(for: Date()))!

    static func now() -> Date { Date() }

    /// `apple_to_dt`: Core Data seconds (or Messages nanoseconds) → Date, nil for 0 and sentinels.
    static func appleToDate(_ raw: Double?) -> Date? {
        guard var v = raw, v != 0, v.isFinite else { return nil }
        if v > 1e12 { v /= 1e9 }
        return fromTimestamp(v + appleEpoch)
    }

    static func appleToDate(_ value: SQLValue) -> Date? { appleToDate(value.double) }

    static func dateToApple(_ d: Date) -> Double { d.timeIntervalSince1970 - appleEpoch }

    /// `datetime.fromtimestamp` rounded to whole seconds the way CPython does, nil outside years 1–9999.
    static func fromTimestamp(_ t: Double) -> Date? {
        guard t.isFinite, t > -62_135_596_800, t < 253_402_300_800 else { return nil }
        var whole = t.rounded(.towardZero)
        let frac = t - whole
        var us = (frac * 1e6).rounded(.toNearestOrEven)
        if us >= 1_000_000 { whole += 1; us -= 1_000_000 } else if us < 0 { whole -= 1 }
        return Date(timeIntervalSince1970: whole)
    }

    /// `iso(dt)`: RFC 3339 in the local offset, seconds precision.
    static func iso(_ d: Date?) -> String? {
        guard let d else { return nil }
        return format(d, "yyyy-MM-dd'T'HH:mm:ssxxxxx")
    }

    static func iso(_ d: Date) -> String { format(d, "yyyy-MM-dd'T'HH:mm:ssxxxxx") }

    /// `day_of(dt)`
    static func day(of d: Date) -> String { format(d, "yyyy-MM-dd") }

    /// `day_bounds(day)`
    static func dayBounds(_ day: String) -> (start: Date, end: Date)? {
        guard let start = parseDay(day) else { return nil }
        return (start, start.addingTimeInterval(86_400))
    }

    static func parseDay(_ day: String) -> Date? {
        let parts = day.split(separator: "-")
        guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        var comps = DateComponents()
        comps.year = y; comps.month = m; comps.day = d
        comps.hour = 0; comps.minute = 0; comps.second = 0
        return calendar.date(from: comps)
    }

    /// `parse_iso(s)`: Python's `datetime.fromisoformat`, naive → local, then normalised to the local offset.
    static func parseISO(_ text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        let s = text.replacingOccurrences(of: "Z", with: "+00:00")
        guard let m = isoRegex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        func group(_ i: Int) -> String? {
            let r = m.range(at: i)
            guard r.location != NSNotFound, let range = Range(r, in: s) else { return nil }
            return String(s[range])
        }
        guard let y = Int(group(1) ?? ""), let mo = Int(group(2) ?? ""), let d = Int(group(3) ?? "") else { return nil }
        var comps = DateComponents()
        comps.year = y; comps.month = mo; comps.day = d
        comps.hour = Int(group(4) ?? "0") ?? 0
        comps.minute = Int(group(5) ?? "0") ?? 0
        comps.second = Int(group(6) ?? "0") ?? 0
        var tz = localTZ
        if let off = group(8) {
            let sign = off.hasPrefix("-") ? -1 : 1
            let digits = off.dropFirst().replacingOccurrences(of: ":", with: "")
            let hh = Int(digits.prefix(2)) ?? 0
            let mm = digits.count >= 4 ? (Int(digits.dropFirst(2).prefix(2)) ?? 0) : 0
            tz = TimeZone(secondsFromGMT: sign * (hh * 3600 + mm * 60)) ?? localTZ
        }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        guard let date = cal.date(from: comps) else { return nil }
        // Python keeps microseconds; nothing downstream prints them, and iso() truncates to seconds.
        return date
    }

    private static let isoRegex = try! NSRegularExpression(
        pattern: #"^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2})(?::(\d{2})(?:[.,](\d{1,6}))?)?)?([+-]\d{2}(?::?\d{2})?)?$"#)

    /// `datetime.strptime(s, "%Y-%m-%d %H:%M:%S %z")` for Health Auto Export.
    static func parseHAE(_ s: String) -> Date? {
        guard let m = haeRegex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return parseISO(s) }
        func group(_ i: Int) -> String { let r = Range(m.range(at: i), in: s)!; return String(s[r]) }
        var comps = DateComponents()
        comps.year = Int(group(1)); comps.month = Int(group(2)); comps.day = Int(group(3))
        comps.hour = Int(group(4)); comps.minute = Int(group(5)); comps.second = Int(group(6))
        let off = group(7)
        let sign = off.hasPrefix("-") ? -1 : 1
        let hh = Int(off.dropFirst().prefix(2)) ?? 0, mm = Int(off.dropFirst(3).prefix(2)) ?? 0
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: sign * (hh * 3600 + mm * 60)) ?? localTZ
        return cal.date(from: comps)
    }

    private static let haeRegex = try! NSRegularExpression(pattern: #"^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2}) ([+-]\d{4})$"#)

    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = localTZ
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }()

    private static let formatterLock = NSLock()
    private static var formatters: [String: DateFormatter] = [:]

    /// strftime in the local offset, C locale. Patterns are Unicode (DateFormatter) patterns.
    static func format(_ d: Date, _ pattern: String) -> String {
        formatterLock.lock()
        defer { formatterLock.unlock() }
        let f: DateFormatter
        if let cached = formatters[pattern] {
            f = cached
        } else {
            f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = localTZ
            f.calendar = Calendar(identifier: .gregorian)
            f.dateFormat = pattern
            formatters[pattern] = f
        }
        return f.string(from: d)
    }

    /// `%H:%M`
    static func hhmm(_ d: Date) -> String { format(d, "HH:mm") }
}

// MARK: - Ids and text (util.py)

enum Util {
    /// `stable_id(*parts)`: sha1 of the parts joined by "|", first 20 hex chars.
    static func stableID(_ parts: Any?...) -> String {
        let joined = parts.map { Py.str($0) }.joined(separator: "|")
        let digest = Insecure.SHA1.hash(data: Data(joined.utf8))
        return String(digest.map { String(format: "%02x", $0) }.joined().prefix(20))
    }

    /// `human_duration(seconds)`
    static func humanDuration(_ seconds: Double?) -> String {
        guard let seconds, seconds != 0 else { return "0m" }
        let total = Int(seconds.rounded(.towardZero))
        let h = total / 3600, rem = total % 3600
        let m = rem / 60, s = rem % 60
        if h != 0 { return "\(h)h\(String(format: "%02d", m))m" }
        if m != 0 { return (s != 0 && m < 5) ? "\(m)m\(String(format: "%02d", s))s" : "\(m)m" }
        return "\(s)s"
    }

    /// `excerpt(text, n)`: whitespace collapsed, cut at n code points with an ellipsis.
    static func excerpt(_ text: String?, _ n: Int = 240) -> String {
        guard let text, !text.isEmpty else { return "" }
        let t = Py.split(text).joined(separator: " ")
        if Py.len(t) <= n { return t }
        return Py.rstrip(Py.prefix(t, n - 1)) + "…"
    }
}

// MARK: - JSON with Python's serialisation (ordered keys, int/float kept apart, ensure_ascii=False)

indirect enum JSON: Equatable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([JSON])
    case object([(String, JSON)])

    static func == (a: JSON, b: JSON) -> Bool { a.dumps() == b.dumps() }

    // Accessors ----------------------------------------------------------------------------------

    subscript(key: String) -> JSON? {
        if case .object(let pairs) = self { return pairs.first { $0.0 == key }?.1 }
        return nil
    }

    var isNull: Bool { if case .null = self { return true }; return false }
    var string: String? { if case .string(let s) = self { return s }; return nil }
    var bool: Bool? { if case .bool(let b) = self { return b }; return nil }
    var int: Int64? {
        switch self {
        case .int(let i): return i
        case .double(let d): return d.isFinite && d == d.rounded() ? Int64(d) : nil
        default: return nil
        }
    }
    var double: Double? {
        switch self {
        case .int(let i): return Double(i)
        case .double(let d): return d
        default: return nil
        }
    }
    var isNumber: Bool { if case .int = self { return true }; if case .double = self { return true }; return false }
    var array: [JSON]? { if case .array(let a) = self { return a }; return nil }
    var pairs: [(String, JSON)]? { if case .object(let p) = self { return p }; return nil }

    /// Python truthiness.
    var truthy: Bool {
        switch self {
        case .null: return false
        case .bool(let b): return b
        case .int(let i): return i != 0
        case .double(let d): return d != 0
        case .string(let s): return !s.isEmpty
        case .array(let a): return !a.isEmpty
        case .object(let p): return !p.isEmpty
        }
    }

    /// `str(value)`
    var pyStr: String {
        switch self {
        case .null: return "None"
        case .bool(let b): return b ? "True" : "False"
        case .int(let i): return String(i)
        case .double(let d): return Py.repr(d)
        case .string(let s): return s
        default: return dumps()
        }
    }

    /// dict.get with a default, honouring key order semantics of `d[k] = v`.
    mutating func set(_ key: String, _ value: JSON) {
        guard case .object(var pairs) = self else { return }
        if let i = pairs.firstIndex(where: { $0.0 == key }) { pairs[i].1 = value } else { pairs.append((key, value)) }
        self = .object(pairs)
    }

    /// `dict.update(other)`
    mutating func update(_ other: JSON) {
        guard case .object(let others) = other else { return }
        for (k, v) in others { set(k, v) }
    }

    // Serialisation -------------------------------------------------------------------------------

    /// `json.dumps(v, ensure_ascii=False)`; `indent` as in Python.
    func dumps(indent: Int? = nil) -> String {
        var out = ""
        write(to: &out, indent: indent, level: 0)
        return out
    }

    private func write(to out: inout String, indent: Int?, level: Int) {
        switch self {
        case .null: out += "null"
        case .bool(let b): out += b ? "true" : "false"
        case .int(let i): out += String(i)
        case .double(let d):
            if d.isNaN { out += "NaN" } else if d.isInfinite { out += d < 0 ? "-Infinity" : "Infinity" } else { out += Py.repr(d) }
        case .string(let s): out += JSON.quote(s)
        case .array(let items):
            if items.isEmpty { out += "[]"; return }
            out += "["
            for (i, item) in items.enumerated() {
                if i > 0 { out += indent == nil ? ", " : "," }
                if let indent { out += "\n" + String(repeating: " ", count: indent * (level + 1)) }
                item.write(to: &out, indent: indent, level: level + 1)
            }
            if let indent { out += "\n" + String(repeating: " ", count: indent * level) }
            out += "]"
        case .object(let pairs):
            if pairs.isEmpty { out += "{}"; return }
            out += "{"
            for (i, (k, v)) in pairs.enumerated() {
                if i > 0 { out += indent == nil ? ", " : "," }
                if let indent { out += "\n" + String(repeating: " ", count: indent * (level + 1)) }
                out += JSON.quote(k) + ": "
                v.write(to: &out, indent: indent, level: level + 1)
            }
            if let indent { out += "\n" + String(repeating: " ", count: indent * level) }
            out += "}"
        }
    }

    static func quote(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if scalar.value < 0x20 { out += String(format: "\\u%04x", scalar.value) } else { out.unicodeScalars.append(scalar) }
            }
        }
        return out + "\""
    }

    // Parsing -------------------------------------------------------------------------------------

    static func parse(_ text: String) -> JSON? { parse(Data(text.utf8)) }

    static func parse(_ data: Data) -> JSON? {
        var p = Parser(bytes: [UInt8](data))
        p.skipWhitespace()
        guard let v = p.value() else { return nil }
        p.skipWhitespace()
        return p.i == p.bytes.count ? v : nil
    }

    private struct Parser {
        let bytes: [UInt8]
        var i = 0

        init(bytes: [UInt8]) { self.bytes = bytes }

        mutating func skipWhitespace() {
            while i < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[i]) { i += 1 }
        }

        mutating func value() -> JSON? {
            guard i < bytes.count else { return nil }
            switch bytes[i] {
            case UInt8(ascii: "{"): return object()
            case UInt8(ascii: "["): return array()
            case UInt8(ascii: "\""): return string().map { .string($0) }
            case UInt8(ascii: "t"): return literal("true", .bool(true))
            case UInt8(ascii: "f"): return literal("false", .bool(false))
            case UInt8(ascii: "n"): return literal("null", .null)
            case UInt8(ascii: "N"): return literal("NaN", .double(.nan))
            case UInt8(ascii: "I"): return literal("Infinity", .double(.infinity))
            default: return number()
            }
        }

        mutating func literal(_ word: String, _ v: JSON) -> JSON? {
            let w = Array(word.utf8)
            guard i + w.count <= bytes.count, Array(bytes[i ..< i + w.count]) == w else { return nil }
            i += w.count
            return v
        }

        mutating func number() -> JSON? {
            let start = i
            if i < bytes.count, bytes[i] == UInt8(ascii: "-") { i += 1 }
            if i < bytes.count, bytes[i] == UInt8(ascii: "I") { return literal("Infinity", .double(-.infinity)) }
            var isFloat = false
            while i < bytes.count {
                let b = bytes[i]
                if b >= 0x30, b <= 0x39 { i += 1; continue }
                if b == UInt8(ascii: "."), !isFloat { isFloat = true; i += 1; continue }
                if b == UInt8(ascii: "e") || b == UInt8(ascii: "E") {
                    isFloat = true; i += 1
                    if i < bytes.count, bytes[i] == UInt8(ascii: "+") || bytes[i] == UInt8(ascii: "-") { i += 1 }
                    continue
                }
                break
            }
            guard i > start, let text = String(bytes: bytes[start ..< i], encoding: .utf8) else { return nil }
            if !isFloat, let n = Int64(text) { return .int(n) }
            return Double(text).map { .double($0) }
        }

        mutating func string() -> String? {
            guard bytes[i] == UInt8(ascii: "\"") else { return nil }
            i += 1
            var out = [UInt8]()
            while i < bytes.count {
                let b = bytes[i]
                if b == UInt8(ascii: "\"") { i += 1; return String(bytes: out, encoding: .utf8) }
                if b == UInt8(ascii: "\\") {
                    i += 1
                    guard i < bytes.count else { return nil }
                    let e = bytes[i]
                    i += 1
                    switch e {
                    case UInt8(ascii: "\""): out.append(0x22)
                    case UInt8(ascii: "\\"): out.append(0x5C)
                    case UInt8(ascii: "/"): out.append(0x2F)
                    case UInt8(ascii: "b"): out.append(0x08)
                    case UInt8(ascii: "f"): out.append(0x0C)
                    case UInt8(ascii: "n"): out.append(0x0A)
                    case UInt8(ascii: "r"): out.append(0x0D)
                    case UInt8(ascii: "t"): out.append(0x09)
                    case UInt8(ascii: "u"):
                        guard let cp = hex4() else { return nil }
                        var scalarValue = UInt32(cp)
                        if cp >= 0xD800, cp < 0xDC00, i + 1 < bytes.count, bytes[i] == UInt8(ascii: "\\"), bytes[i + 1] == UInt8(ascii: "u") {
                            i += 2
                            guard let lo = hex4() else { return nil }
                            scalarValue = 0x10000 + ((UInt32(cp) - 0xD800) << 10) + (UInt32(lo) - 0xDC00)
                        }
                        let scalar = Unicode.Scalar(scalarValue) ?? "\u{FFFD}"
                        out.append(contentsOf: Array(String(scalar).utf8))
                    default: return nil
                    }
                } else {
                    out.append(b); i += 1
                }
            }
            return nil
        }

        mutating func hex4() -> UInt16? {
            guard i + 4 <= bytes.count, let s = String(bytes: bytes[i ..< i + 4], encoding: .utf8), let v = UInt16(s, radix: 16) else { return nil }
            i += 4
            return v
        }

        mutating func array() -> JSON? {
            i += 1
            var items: [JSON] = []
            skipWhitespace()
            if i < bytes.count, bytes[i] == UInt8(ascii: "]") { i += 1; return .array(items) }
            while true {
                skipWhitespace()
                guard let v = value() else { return nil }
                items.append(v)
                skipWhitespace()
                guard i < bytes.count else { return nil }
                if bytes[i] == UInt8(ascii: ",") { i += 1; continue }
                if bytes[i] == UInt8(ascii: "]") { i += 1; return .array(items) }
                return nil
            }
        }

        mutating func object() -> JSON? {
            i += 1
            var pairs: [(String, JSON)] = []
            skipWhitespace()
            if i < bytes.count, bytes[i] == UInt8(ascii: "}") { i += 1; return .object(pairs) }
            while true {
                skipWhitespace()
                guard i < bytes.count, bytes[i] == UInt8(ascii: "\""), let k = string() else { return nil }
                skipWhitespace()
                guard i < bytes.count, bytes[i] == UInt8(ascii: ":") else { return nil }
                i += 1
                skipWhitespace()
                guard let v = value() else { return nil }
                if let idx = pairs.firstIndex(where: { $0.0 == k }) { pairs[idx].1 = v } else { pairs.append((k, v)) }
                skipWhitespace()
                guard i < bytes.count else { return nil }
                if bytes[i] == UInt8(ascii: ",") { i += 1; continue }
                if bytes[i] == UInt8(ascii: "}") { i += 1; return .object(pairs) }
                return nil
            }
        }
    }
}

extension JSON {
    /// A convenience for building objects in source order: `JSON.obj([("a", .int(1))])`.
    static func obj(_ pairs: [(String, JSON)]) -> JSON { .object(pairs) }
    static func str(_ s: String?) -> JSON { s.map { .string($0) } ?? .null }
    static func num(_ i: Int) -> JSON { .int(Int64(i)) }
}
