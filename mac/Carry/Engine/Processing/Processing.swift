import Foundation

/// What Pro unlocks and nothing else: turning pictures and audio into text on this Mac (processing.py).
enum Processing {
    static func pendingCounts(_ store: Store) -> [String: Int] {
        [
            "screenshots": (try? store.pending("screenshots", limit: 10_000).count) ?? 0,
            "photos": (try? store.pending("photos", limit: 10_000).count) ?? 0,
            "voice_memos": (try? store.pending("voice_memos", limit: 10_000).count) ?? 0,
            "inbox": (try? store.pending("inbox", limit: 10_000).filter { $0.kind == "image" }.count) ?? 0,
        ]
    }

    /// Process items that still lack text. Returns counts per source. Does nothing without Pro.
    static func run(store: Store, proc: JSON, pro: Bool, limit: Int = 60, log: (String) -> Void = { _ in }) -> [String: Int] {
        var done = ["screenshots": 0, "photos": 0, "inbox": 0, "voice_memos": 0]
        guard pro else { return done }
        let fm = FileManager.default
        if proc["ocr"]?.truthy ?? true {
            var targets: [(String, [Item])] = [("screenshots", (try? store.pending("screenshots", limit: limit)) ?? [])]
            if proc["ocr_photos"]?.truthy == true {
                targets.append(("photos", (try? store.pending("photos", limit: limit)) ?? []))
            }
            targets.append(("inbox", ((try? store.pending("inbox", limit: limit)) ?? []).filter { $0.kind == "image" }))
            for (source, rows) in targets {
                for r in rows {
                    guard let path = r.path, fm.fileExists(atPath: path) else {
                        try? store.setProcessed(id: r.id, text: r.text, extraMeta: .object([("ocr", .string("missing-file"))]))
                        continue
                    }
                    let text = VisionOCR.recognize(path: path)
                    let base = source == "inbox" ? r.text : nil
                    let merged = [base, text].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
                    try? store.setProcessed(id: r.id, text: merged.isEmpty ? nil : merged,
                                            extraMeta: .object([("ocr", .string("vision")), ("ocr_chars", .num(Py.len(text ?? "")))]))
                    done[source, default: 0] += 1
                    log("  ocr  \(source.padding(toLength: 12, withPad: " ", startingAt: 0)) \(Util.excerpt(text, 60).isEmpty ? "(no text)" : Util.excerpt(text, 60))")
                }
            }
            store.commit()
        }
        if proc["transcribe"]?.truthy ?? true {
            let maxS = (proc["transcribe_max_minutes"]?.double ?? 90) * 60
            var perRun = Int(proc["max_transcriptions_per_run"]?.int ?? 3)
            for r in (try? store.pending("voice_memos", limit: limit)) ?? [] {
                guard let path = r.path, fm.fileExists(atPath: path) else {
                    try? store.setProcessed(id: r.id, text: nil, extraMeta: .object([("transcript", .string("missing-file"))]))
                    continue
                }
                var seconds = r.meta["duration_s"]?.double ?? 0
                if seconds == 0 { seconds = Transcribe.seconds(path: path) ?? 0 }
                if seconds > maxS {
                    try? store.setProcessed(id: r.id, text: nil, extraMeta: .object([("transcript", .string("skipped-too-long")),
                                                                                     ("duration_s", .num(Py.roundInt(seconds)))]))
                    continue
                }
                if perRun <= 0 { break }
                perRun -= 1
                log("  transcribe \(Py.prefix(r.titleOrEmpty, 40)) (\(Py.fixed(seconds / 60, 0)) min)…")
                let began = Date()
                let (text, err) = Transcribe.audio(path: path)
                log("  transcribed \(Py.len(text ?? "")) chars in \(Py.fixed(Date().timeIntervalSince(began), 1)) s" + (err.map { " (\($0))" } ?? ""))
                try? store.setProcessed(id: r.id, text: text, extraMeta: .object([
                    ("transcript", .string(text != nil ? "speech" : "failed")), ("model", .string(Transcribe.engineName)),
                    ("duration_s", .num(Py.roundInt(seconds))), ("error", .str(err)),
                ]))
                done["voice_memos", default: 0] += 1
                store.commit()
            }
        }
        return done
    }
}
