import Foundation

/// iMessage and SMS from ~/Library/Messages/chat.db (needs Full Disk Access). Off by default.
enum MessagesReader: Reader {
    static let db = Readers.home.appendingPathComponent("Library/Messages/chat.db")
    static let addressBookSources = Readers.home.appendingPathComponent("Library/Application Support/AddressBook/Sources", isDirectory: true)

    static func available() -> (Bool, String) {
        guard FileManager.default.fileExists(atPath: db.path) else { return (false, "No Messages database") }
        do {
            let con = try SQLiteDB.openReadOnly(db.path)
            defer { con.close() }
            return (true, Readers.countNote(try con.scalar("select count(*) from message"), "messages"))
        } catch {
            return (false, "Cannot read chat.db (\(error)). Grant Full Disk Access to your terminal.")
        }
    }

    /// `_norm(handle)`: emails lower-cased; phones reduced to their last 10 digits.
    static func norm(_ handle: String) -> String {
        let h = Py.strip(handle).lowercased()
        if h.contains("@") { return h }
        let digits = h.unicodeScalars.filter { $0.properties.numericType == .decimal || $0.properties.numericType == .digit }
        let s = String(String.UnicodeScalarView(digits))
        return s.count >= 10 ? String(s.suffix(10)) : s
    }

    /// handle (normalised phone digits or email) → 'First Last', from the local Contacts store.
    static func contactNames() -> [String: String] {
        var names: [String: String] = [:]
        guard let sources = try? FileManager.default.contentsOfDirectory(atPath: addressBookSources.path) else { return names }
        for src in sources.sorted() {
            let file = addressBookSources.appendingPathComponent(src).appendingPathComponent("AddressBook-v22.abcddb")
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            do {
                let con = try SQLiteDB.openReadOnly(file.path)
                defer { con.close() }
                var people: [Int64: String] = [:]
                for r in try con.query("select Z_PK, ZFIRSTNAME, ZLASTNAME, ZORGANIZATION from ZABCDRECORD") {
                    let parts = [r["ZFIRSTNAME"].string, r["ZLASTNAME"].string].compactMap { $0 }.filter { !$0.isEmpty }
                    var name = Py.strip(parts.joined(separator: " "))
                    if name.isEmpty { name = r["ZORGANIZATION"].string ?? "" }
                    if let pk = r["Z_PK"].int { people[pk] = name }
                }
                for r in try con.query("select ZOWNER, ZFULLNUMBER from ZABCDPHONENUMBER") {
                    if let number = r["ZFULLNUMBER"].string, !number.isEmpty, let owner = r["ZOWNER"].int, let who = people[owner], !who.isEmpty {
                        names[norm(number)] = who
                    }
                }
                for r in try con.query("select ZOWNER, ZADDRESS from ZABCDEMAILADDRESS") {
                    if let address = r["ZADDRESS"].string, !address.isEmpty, let owner = r["ZOWNER"].int, let who = people[owner], !who.isEmpty {
                        names[norm(address)] = who
                    }
                }
            } catch {
                continue
            }
        }
        return names
    }

    static func collect(store: Store, cfg: JSON, backfillStart: Date, enabled: [String: Bool]) throws -> Int {
        let con = try SQLiteDB.openReadOnly(db.path)
        defer { con.close() }
        let names = contactNames()
        let cursor = try store.getCursor("messages")
        let since = cursor.flatMap { Double($0) } ?? PyTime.dateToApple(backfillStart) * 1e9
        let rows = try con.query(
            """
            select m.ROWID, m.guid, m.date, m.is_from_me, m.text, m.attributedBody, m.cache_has_attachments,
                      h.id as handle, c.chat_identifier, c.display_name, c.ROWID as chat_id, c.style
               from message m
               left join handle h on h.ROWID = m.handle_id
               left join chat_message_join cmj on cmj.message_id = m.ROWID
               left join chat c on c.ROWID = cmj.chat_id
               where m.date > ? order by m.date
            """, [.double(since)])
        var new = 0
        var last = since
        for r in rows {
            guard let ts = PyTime.appleToDate(r["date"]) else { continue }
            var text = Py.strip(r["text"].string ?? "")
            if text.isEmpty { text = Decoders.attributedBody(r["attributedBody"].data) ?? "" }
            let hasAttachment = r["cache_has_attachments"].truthy
            if text.isEmpty, !hasAttachment {
                last = max(last, r["date"].double ?? 0)
                continue
            }
            let handle = r["handle"].string ?? ""
            let known = handle.isEmpty ? nil : names[norm(handle)]
            let who = known ?? (handle.isEmpty ? "me" : handle)
            let displayName = Py.strip(r["display_name"].string ?? "")
            // Numeric senders without a contact (10086, 1069…) are notifications, not people.
            let stripped = String(handle.drop(while: { $0 == "+" }))
            let notification = !handle.isEmpty && known == nil && Py.isDigit(stripped) && displayName.isEmpty
            let chatLabel = !displayName.isEmpty ? displayName : (!who.isEmpty ? who : (r["chat_identifier"].string.flatMap { $0.isEmpty ? nil : $0 } ?? "unknown"))
            let fromMe = r["is_from_me"].truthy
            let meta: JSON = .object([
                ("from_me", .bool(fromMe)), ("handle", .string(handle)), ("sender", .string(fromMe ? "me" : who)),
                ("chat_id", r["chat_id"].json), ("group", .bool(r["style"].int == 43)), ("attachment", .bool(hasAttachment)),
                ("notification", .bool(notification)),
            ])
            if try store.upsert(id: Util.stableID("msg", r["guid"]), source: "messages", kind: "message", ts: ts,
                                title: chatLabel, text: text.isEmpty ? "[attachment]" : text, meta: meta) {
                new += 1
            }
            last = max(last, r["date"].double ?? 0)
        }
        try store.setCursor("messages", String(Int64(last)), count: new)
        return new
    }
}
