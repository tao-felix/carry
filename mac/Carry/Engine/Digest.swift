import Foundation

/// The product: one Markdown file per day that any agent can read, plus a rolling week and a README.
/// Section order, wording and excerpt lengths are those of cli/src/carry/digest.py, so the file is the same
/// whether the CLI or this app wrote it.
enum Digest {
    static let asleep: Set<String> = ["core", "deep", "rem", "asleepUnspecified"]

    /// `_t(row)`
    private static func t(_ row: Item) -> String {
        PyTime.parseISO(row.ts).map { PyTime.hhmm($0) } ?? ""
    }

    /// `_health_summary(store, day)`
    static func healthSummary(_ store: Store, _ day: String) throws -> [String] {
        guard let (start, end) = PyTime.dayBounds(day) else { return [] }
        var lines: [String] = []
        // Last night's sleep: stage records that end between 00:00 and 14:00 of `day`.
        let sleep = try store.endingBetween("health", kind: "sleep", start, start.addingTimeInterval(14 * 3600))
        if !sleep.isEmpty {
            var by: [String: Double] = [:]
            var first: Date? = nil, last: Date? = nil
            for r in sleep {
                guard let s = PyTime.parseISO(r.ts), let e = PyTime.parseISO(r.tsEnd) else { continue }
                let stage = r.meta["v"]?.pyStr ?? "None"
                by[stage, default: 0] += e.timeIntervalSince(s)
                if asleep.contains(stage) {
                    first = (first == nil || s < first!) ? s : first
                    last = (last == nil || e > last!) ? e : last
                }
            }
            let asleepSeconds = by.filter { asleep.contains($0.key) }.values.reduce(0, +)
            if asleepSeconds != 0 {
                var parts = ["Sleep \(Util.humanDuration(asleepSeconds))"]
                if let first, let last { parts.append("\(PyTime.hhmm(first))–\(PyTime.hhmm(last))") }
                for (k, label) in [("deep", "deep"), ("rem", "REM"), ("core", "core"), ("awake", "awake")] {
                    if let v = by[k], v != 0 { parts.append("\(label) \(Util.humanDuration(v))") }
                }
                lines.append(parts.joined(separator: " · "))
            }
        }
        let steps = try store.between("health", start, end, kind: "steps").reduce(0.0) { $0 + ($1.meta["v"]?.double ?? 0) }
        if steps != 0 { lines.append("Steps \(Py.thousands(Int(steps.rounded(.towardZero))))") }
        let rhr = try store.between("health", start, end, kind: "resting_heart_rate")
        let hrv = try store.between("health", start, end, kind: "hrv")
        var bits: [String] = []
        if let lastRHR = rhr.last { bits.append("resting HR \(lastRHR.meta["v"]?.pyStr ?? "None") bpm") }
        if !hrv.isEmpty {
            let vals = hrv.map { $0.meta["v"]?.double ?? 0 }
            bits.append("HRV \(Py.fixed(vals.reduce(0, +) / Double(vals.count), 0)) ms")
        }
        let hr = try store.between("health", start, end, kind: "heart_rate")
        if !hr.isEmpty {
            let vals = hr.map { $0.meta["v"]?.double ?? 0 }
            bits.append("HR \(Py.fixed(vals.min()!, 0))–\(Py.fixed(vals.max()!, 0))")
        }
        if !bits.isEmpty { lines.append(bits.joined(separator: " · ")) }
        let energy = try store.between("health", start, end, kind: "active_energy").reduce(0.0) { $0 + ($1.meta["v"]?.double ?? 0) }
        if energy != 0 { lines.append("Active energy \(Py.fixed(energy, 0)) kcal") }
        for r in try store.between("health", start, end, kind: "workout") {
            let m = r.meta
            var extra: [String] = []
            if let d = m["distance_m"], d.truthy, let dm = d.double { extra.append("\(Py.fixed(dm / 1000, 1)) km") }
            if let e = m["energy_kcal"], e.truthy, let ek = e.double { extra.append("\(Py.fixed(ek, 0)) kcal") }
            let s = PyTime.parseISO(r.ts), e = PyTime.parseISO(r.tsEnd)
            let dur = (s != nil && e != nil) ? Util.humanDuration(e!.timeIntervalSince(s!)) : ""
            lines.append("Workout \(m["v"]?.pyStr ?? "None") \(dur) " + extra.joined(separator: " "))
        }
        for (kind, label, unit) in [("body_mass", "Weight", "kg"), ("blood_oxygen", "SpO₂", "")] {
            let rows = try store.between("health", start, end, kind: kind)
            if let lastRow = rows.last {
                let v = lastRow.meta["v"] ?? .null
                // `isinstance(v, (int, float))` is true for bools too in Python.
                let numeric: Double? = v.bool.map { $0 ? 1 : 0 } ?? (v.isNumber ? v.double : nil)
                if kind == "blood_oxygen", let d = numeric {
                    lines.append("\(label) \(Py.fixed(d * 100, 0))%")
                } else {
                    lines.append(Py.strip("\(label) \(v.pyStr) \(unit)"))
                }
            }
        }
        return lines
    }

    /// `build_day(store, day, enabled, pro, decided_by)`
    static func buildDay(_ store: Store, day: String, enabled: [String: Bool], pro: Bool, decidedBy: String) throws -> String {
        guard let (start, end) = PyTime.dayBounds(day) else { return "" }
        let weekday = PyTime.format(start, "EEEE")
        var out: [String] = ["# \(day) (\(weekday))", "",
                             "_Carry digest · generated \(PyTime.format(PyTime.now(), "yyyy-MM-dd HH:mm")) · sources chosen on the \(decidedBy)"
                                 + " · Pro \(pro ? "on" : "off")_", ""]
        var empty: [String] = []

        func section(_ title: String, _ lines: [String]) {
            if !lines.isEmpty {
                out.append("## \(title)")
                out.append(contentsOf: lines)
                out.append("")
            } else {
                empty.append(title)
            }
        }
        func on(_ name: String) -> Bool { enabled[name] ?? false }

        // Inbox first: what the user deliberately sent.
        if on("inbox") {
            var lines: [String] = []
            let rows = try store.dayItems(day, source: "inbox")
            for r in rows {
                let m = r.meta
                var head = "- \(t(r)) **\(r.title ?? "None")**"
                if let url = m["url"], url.truthy { head += " <\(url.pyStr)>" }
                if let app = m["from_app"], app.truthy { head += " _(from \(Apps.name(app.pyStr)))_" }
                lines.append(head)
                let note = m["note"]
                if let note, note.truthy { lines.append("  - note: \(note.pyStr)") }
                var body = Py.strip(r.textOrEmpty)
                if let note, note.truthy, body.hasPrefix(note.pyStr) { body = Py.strip(Py.dropFirst(body, Py.len(note.pyStr))) }
                if !body.isEmpty { lines.append("  - \(Util.excerpt(body, 400))") }
            }
            // `len(lines and store.day_items(day, 'inbox'))`: the item count when there are lines, else 0.
            section("Inbox (\(lines.isEmpty ? 0 : rows.count))", lines)
        }

        if on("health") {
            section("Health", try healthSummary(store, day).map { "- \($0)" })
        }

        if on("location") {
            var lines: [String] = []
            for r in try store.between("location", start, end, kind: "visit") {
                let s = PyTime.parseISO(r.ts), e = PyTime.parseISO(r.tsEnd)
                let span: String
                if let s, let e { span = "\(PyTime.hhmm(s))–\(PyTime.hhmm(e))" } else if let s { span = PyTime.hhmm(s) } else { span = "" }
                let m = r.meta
                let place = (m["place"]?.truthy == true) ? m["place"]!.pyStr : "\(m["lat"]?.pyStr ?? "None"), \(m["lon"]?.pyStr ?? "None")"
                lines.append("- \(span) \(place)")
            }
            section("Places", lines)
        }

        if on("screenshots") {
            let rows = try store.dayItems(day, source: "screenshots")
            var lines: [String] = []
            for r in rows.prefix(12) {
                let text = Util.excerpt(r.text, 220)
                lines.append("- \(t(r)) " + (!text.isEmpty ? text : (!pro ? "_(no text yet, Pro is off)_" : "_(no text found)_")))
            }
            if rows.count > 12 { lines.append("- … \(rows.count - 12) more, `carry recent screenshots`") }
            section("Screenshots (\(rows.count))", lines)
        }

        if on("photos") {
            let rows = try store.dayItems(day, source: "photos")
            var lines: [String] = []
            let places = rows.filter { $0.meta["lat"] != nil && $0.meta["lat"]?.isNull == false }.count
            var kindOrder: [String] = []
            var kinds: [String: Int] = [:]
            for r in rows {
                if kinds[r.kind] == nil { kindOrder.append(r.kind) }
                kinds[r.kind, default: 0] += 1
            }
            if !rows.isEmpty {
                let summary = kindOrder.map { k in "\(kinds[k]!) \(k)\(kinds[k]! > 1 ? "s" : "")" }.joined(separator: ", ")
                lines.append("- " + summary + (places != 0 ? ", \(places) with location" : ""))
            }
            for r in rows where !(r.text ?? "").isEmpty {
                lines.append("- \(t(r)) \(Util.excerpt(r.text, 200))")
            }
            section("Photos (\(rows.count))", lines)
        }

        if on("voice_memos") {
            let rows = try store.dayItems(day, source: "voice_memos")
            var lines: [String] = []
            for r in rows {
                let m = r.meta
                lines.append("- \(t(r)) **\(r.title ?? "None")** (\(Util.humanDuration(m["duration_s"]?.double)))")
                if let text = r.text, !text.isEmpty {
                    lines.append("  - \(Util.excerpt(text, 600))")
                } else if !pro {
                    lines.append("  - _(transcript needs Pro)_")
                }
            }
            section("Voice memos (\(rows.count))", lines)
        }

        if on("notes") {
            let rows = try store.dayItems(day, source: "notes")
            var lines: [String] = []
            for r in rows {
                let m = r.meta
                let folder = (m["folder"]?.truthy == true) ? " _(\(m["folder"]!.pyStr))_" : ""
                lines.append("- \(t(r)) **\(r.title ?? "None")**\(folder)")
                var body = r.textOrEmpty
                let title = r.titleOrEmpty
                if body.hasPrefix(title) { body = Py.strip(Py.dropFirst(body, Py.len(title))) }
                if !body.isEmpty { lines.append("  - \(Util.excerpt(body, 400))") }
            }
            section("Notes edited (\(rows.count))", lines)
        }

        if on("messages") {
            let rows = try store.dayItems(day, source: "messages")
            var threadOrder: [String] = []
            var threads: [String: [Item]] = [:]
            var notices: [Item] = []
            for r in rows {
                if r.meta["notification"]?.truthy == true {
                    notices.append(r)
                } else {
                    let key = r.title ?? "None"
                    if threads[key] == nil { threadOrder.append(key) }
                    threads[key, default: []].append(r)
                }
            }
            var lines: [String] = []
            // sorted(threads.items(), key=last ts, reverse=True): stable, so ties keep insertion order.
            let ordered = threadOrder.enumerated().sorted { a, b in
                let ta = threads[a.element]!.last!.ts, tb = threads[b.element]!.last!.ts
                return ta != tb ? ta > tb : a.offset < b.offset
            }.map(\.element)
            for name in ordered.prefix(15) {
                let msgs = threads[name]!
                lines.append("- **\(name)** · \(msgs.count) message\(msgs.count > 1 ? "s" : "")")
                for r in msgs.suffix(2) {
                    lines.append("  - \(t(r)) \(r.meta["sender"]?.pyStr ?? ""): \(Util.excerpt(r.text, 160))")
                }
            }
            if !notices.isEmpty {
                var tags: [String] = []
                for r in notices {
                    let text = r.textOrEmpty
                    if let m = notificationTag.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                       let range = Range(m.range(at: 1), in: text) {
                        tags.append(String(text[range]))
                    } else {
                        tags.append(Util.excerpt(text, 24))
                    }
                }
                var seen = Set<String>()
                let unique = tags.filter { seen.insert($0).inserted }
                lines.append("- \(notices.count) SMS notifications: " + unique.joined(separator: "; "))
            }
            section("Messages (\(threads.count) threads, \(notices.count) notifications)", lines)
        } else if enabled["messages"] != nil {
            out.append(contentsOf: ["## Messages", "- off (you chose)", ""])
        }

        if on("calendar") {
            var lines: [String] = []
            for r in try store.between("calendar", start, end) {
                let m = r.meta
                let e = PyTime.parseISO(r.tsEnd)
                let when: String
                if m["all_day"]?.truthy == true { when = "all day" } else if let e { when = "\(t(r))–\(PyTime.hhmm(e))" } else { when = t(r) }
                let cal = (m["calendar"]?.truthy == true) ? " _(\(m["calendar"]!.pyStr))_" : ""
                lines.append("- \(when) \(r.title ?? "None")\(cal)")
            }
            section("Calendar (\(lines.count))", lines)
            var upcomingOrder: [String] = []
            var upcoming: [String: [Item]] = [:]
            for r in try store.between("calendar", end, end.addingTimeInterval(7 * 86_400)) where !(r.meta["all_day"]?.truthy ?? false) {
                let key = r.title ?? "None"
                if upcoming[key] == nil { upcomingOrder.append(key) }
                upcoming[key, default: []].append(r)
            }
            if !upcoming.isEmpty {
                var lines: [String] = []
                for title in upcomingOrder.prefix(8) {
                    let rs = upcoming[title]!
                    let first = PyTime.parseISO(rs[0].ts).map { PyTime.format($0, "EEE dd HH:mm") } ?? ""
                    lines.append("- \(first) \(title)" + (rs.count > 1 ? " _(×\(rs.count) this week)_" : ""))
                }
                out.append("### Next 7 days")
                out.append(contentsOf: lines)
                out.append("")
            }
        }

        if on("reminders") {
            var lines: [String] = []
            var dueToday: [Item] = [], doneToday: [Item] = [], overdue: [Item] = []
            for r in try store.allReminders() {
                let m = r.meta
                let due = PyTime.parseISO(m["due"]?.string), done = PyTime.parseISO(m["completed_at"]?.string)
                let completed = m["completed"]?.truthy ?? false
                if let done, start <= done, done < end {
                    doneToday.append(r)
                } else if !completed, let due, start <= due, due < end {
                    dueToday.append(r)
                } else if !completed, let due, due < start {
                    overdue.append(r)
                }
            }
            for r in dueToday { lines.append("- [ ] \(r.title ?? "None") _(due today)_") }
            for r in doneToday { lines.append("- [x] \(r.title ?? "None")") }
            if !overdue.isEmpty {
                lines.append("- \(overdue.count) overdue: " + overdue.prefix(5).map { $0.title ?? "None" }.joined(separator: "; "))
            }
            section("Reminders", lines)
        }

        if on("safari") {
            let rows = try store.dayItems(day, source: "safari")
            var seen = Set<String>()
            var lines: [String] = []
            for r in rows.reversed() {
                let key = r.text ?? "None"
                if seen.contains(key) { continue }
                seen.insert(key)
                lines.append("- \(t(r)) \(r.title ?? "None") <\(r.text ?? "None")>")
                if lines.count >= 15 { break }
            }
            section("Safari (\(rows.count) visits)", lines)
        }

        if on("screen_time") {
            let items = try store.dayItems(day, source: "screen_time")
            let rows = items.enumerated().sorted { a, b in
                let ma = a.element.meta["minutes"]?.double ?? 0, mb = b.element.meta["minutes"]?.double ?? 0
                return ma != mb ? ma > mb : a.offset < b.offset
            }.map(\.element)
            var deviceOrder: [String] = []
            var byDevice: [String: [Item]] = [:]
            for r in rows {
                let device = r.meta["device"]?.string ?? "mac"
                if byDevice[device] == nil { deviceOrder.append(device) }
                byDevice[device, default: []].append(r)
            }
            var lines: [String] = []
            for device in deviceOrder {
                let top = byDevice[device]!.prefix(8).map { r in
                    "\(r.title ?? "None") \(Util.humanDuration((r.meta["minutes"]?.double ?? 0) * 60))"
                }.joined(separator: ", ")
                lines.append("- \(device): \(top)")
            }
            section("Screen time", lines)
        }

        let blocked = try store.syncStates().filter { st in
            Sources.by(st.source) != nil && (enabled[st.source] ?? false) && (st.lastError ?? "").contains("Full Disk Access")
        }.map { Sources.label($0.source) }
        if !blocked.isEmpty {
            out.append("_Not read in the last sync (needs Full Disk Access, see `carry status`): \(blocked.joined(separator: ", "))_")
        }
        if !empty.isEmpty {
            out.append("_Nothing today: \(empty.joined(separator: ", "))_")
        }
        let off = Sources.all.filter { !(enabled[$0.name] ?? false) && $0.name != "messages" && enabled[$0.name] != nil }.map(\.label)
        if !off.isEmpty {
            out.append("_Switched off: \(off.joined(separator: ", "))_")
        }
        return Py.rstrip(out.joined(separator: "\n")) + "\n"
    }

    private static let notificationTag = try! NSRegularExpression(pattern: #"[【\[]([^】\]]{1,20})[】\]]"#)

    /// `build_week(store, days)`
    static func buildWeek(_ store: Store, days: [String]) throws -> String {
        var out = ["# Last 7 days (\(days.last ?? "") → \(days.first ?? ""))", "",
                   "| day | inbox | shots | photos | memos | notes | sleep | steps | places |",
                   "|---|---|---|---|---|---|---|---|---|"]
        for day in days {
            let c = try store.dayCounts(day)
            let h = try healthSummary(store, day)
            let sleep = h.first { $0.hasPrefix("Sleep") }.map { $0.components(separatedBy: " · ")[0].replacingOccurrences(of: "Sleep ", with: "") } ?? ""
            let steps = h.first { $0.hasPrefix("Steps") }.map { $0.replacingOccurrences(of: "Steps ", with: "") } ?? ""
            var places = 0
            if let (start, end) = PyTime.dayBounds(day) { places = try store.between("location", start, end, kind: "visit").count }
            out.append("| \(day) | \(c["inbox"] ?? 0) | \(c["screenshots"] ?? 0) | \(c["photos"] ?? 0) | \(c["voice_memos"] ?? 0) |"
                + " \(c["notes"] ?? 0) | \(sleep) | \(steps) | \(places) |")
        }
        out.append("")
        out.append("Read a day: `~/.carry/context/<date>.md`. Search anything: `carry search \"<query>\"`.")
        return out.joined(separator: "\n") + "\n"
    }

    static let readme = """
    # Your phone context

    This folder is written by Carry (https://carry.app) on this Mac. It is the living context of the owner's phone.

    - `latest.md` → today. Read it first when a request touches the owner's day, health, places, notes, or things they shared from their phone.
    - `YYYY-MM-DD.md` → one file per day, rewritten every 15 minutes while the Mac is awake.
    - `week.md` → a 7-day table.
    - Full text and older days: `carry search "<query>"` or the `carry` MCP server (`carry mcp`).

    Sources are chosen by the owner on their phone. A section that says "off" was switched off on purpose; do not try to read it elsewhere.
    Nothing here leaves this Mac unless you send it somewhere. Treat it as the owner's private data.

    """

    /// `write_all(...)`: the last `daysBack` days, `latest.md` → today, `week.md`, `README.md`.
    @discardableResult
    static func writeAll(_ store: Store, enabled: [String: Bool], pro: Bool, decidedBy: String, daysBack: Int = 7) throws -> [URL] {
        let dir = CarryPaths.context
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let now = PyTime.now()
        let today = PyTime.day(of: now)
        let days = (0 ..< daysBack).map { PyTime.day(of: now.addingTimeInterval(-Double($0) * 86_400)) }
        var written: [URL] = []
        for day in days {
            let p = dir.appendingPathComponent("\(day).md")
            try buildDay(store, day: day, enabled: enabled, pro: pro, decidedBy: decidedBy).write(to: p, atomically: false, encoding: .utf8)
            written.append(p)
        }
        let latest = dir.appendingPathComponent("latest.md")
        if (try? latest.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true || FileManager.default.fileExists(atPath: latest.path) {
            try? FileManager.default.removeItem(at: latest)
        }
        try FileManager.default.createSymbolicLink(atPath: latest.path, withDestinationPath: "\(today).md")
        try buildWeek(store, days: days).write(to: dir.appendingPathComponent("week.md"), atomically: false, encoding: .utf8)
        try readme.write(to: dir.appendingPathComponent("README.md"), atomically: false, encoding: .utf8)
        return written
    }
}
