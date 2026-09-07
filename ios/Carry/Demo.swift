#if DEBUG
import Foundation

/// Demo fixtures for screenshots and simulator work. Refuses to touch a real iCloud container.
enum Demo {
    static func seed(into store: ContainerStore, forceWelcome: Bool) async {
        guard !store.location.isICloud else { return }
        try? await store.deleteEverything()

        let now = Date()
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: now)
        func at(_ hour: Int, _ minute: Int = 0, dayOffset: Int = 0) -> Date {
            midnight.addingTimeInterval(Double(dayOffset) * 86_400 + Double(hour) * 3600 + Double(minute) * 60)
        }
        let macRead = now.addingTimeInterval(-12 * 60)

        // Heartbeat: what the Mac wrote back 12 minutes ago (§8).
        let heartbeat: [String: Any] = [
            "host": "Tao-MacBook-Pro",
            "carry_version": "0.1.0",
            "last_sync_at": RFC3339.string(macRead),
            "last_digest_date": LocalDay.string(now),
            "counts": ["health": 1234, "location": 12, "inbox": 3, "photos": 40, "screenshots": 6, "notes": 2, "voice_memos": 1],
            "pro": true,
            "sources_applied_at": RFC3339.string(macRead),
        ]
        if let data = try? JSONSerialization.data(withJSONObject: heartbeat, options: [.prettyPrinted, .sortedKeys]) {
            try? await store.writeData(data, to: "heartbeat/Tao-MacBook-Pro.json")
        }

        // Health: a plausible day (§4).
        var records: [HealthRecord] = []
        let watch = "Tao's Apple Watch"
        let stepsByHour = [523, 1210, 340, 880, 1460, 210, 95, 640, 1120, 300, 780, 1590, 410, 260, 920, 130, 60]
        let currentHour = calendar.component(.hour, from: now)
        for hour in 7..<max(7, currentHour) {
            let start = at(hour), end = at(hour + 1)
            let steps = stepsByHour[(hour - 7) % stepsByHour.count]
            records.append(HealthRecord(t: "steps", start: start, end: end, v: .int(steps), u: "count", src: "Health"))
            records.append(HealthRecord(t: "active_energy", start: start, end: end,
                                        v: .double((Double(steps) * 0.045 * 10).rounded() / 10), u: "kcal", src: "Health"))
        }
        var tick = at(7)
        var beat = 0
        while tick < now {
            records.append(HealthRecord(t: "heart_rate", start: tick, end: tick, v: .int(58 + (beat * 7) % 31), u: "bpm", src: watch))
            tick = tick.addingTimeInterval(5 * 60)
            beat += 1
        }
        var bed = at(23, 35, dayOffset: -1)
        for (stage, minutes) in [("core", 75), ("deep", 50), ("rem", 40), ("core", 120), ("awake", 5), ("rem", 60), ("core", 90)] {
            let end = bed.addingTimeInterval(Double(minutes) * 60)
            records.append(HealthRecord(t: "sleep", start: bed, end: end, v: .string(stage), u: "stage", src: watch))
            bed = end
        }
        records.append(HealthRecord(t: "resting_heart_rate", start: at(6, 30), end: at(6, 30), v: .int(54), u: "bpm", src: watch))
        records.append(HealthRecord(t: "hrv", start: at(6, 32), end: at(6, 32), v: .double(48.2), u: "ms", src: watch))
        records.append(HealthRecord(t: "blood_oxygen", start: at(6, 40), end: at(6, 40), v: .double(0.97), u: "ratio", src: watch))
        records.append(HealthRecord(t: "body_mass", start: at(7, 5), end: at(7, 5), v: .double(71.4), u: "kg", src: "Withings"))
        records.append(HealthRecord(t: "workout", start: at(7, 20), end: at(7, 52), v: .string("running"), u: "type", src: watch,
                                    meta: ["distance_m": 5012, "energy_kcal": 410]))
        try? await store.appendHealth(records)

        // Location: two visits, three points (§5).
        try? await store.appendLocation(.visit(arrive: at(9, 12), depart: at(11, 40), lat: 31.2304, lon: 121.4737, accuracyM: 40, place: "Xuhui, Shanghai"))
        try? await store.appendLocation(.visit(arrive: at(12, 5), depart: nil, lat: 31.2244, lon: 121.4790, accuracyM: 35, place: "Xuhui, Shanghai"))
        for (hour, minute) in [(11, 46), (11, 57), (12, 3)] {
            try? await store.appendLocation(.point(ts: at(hour, minute), lat: 31.227, lon: 121.476, accuracyM: 120))
        }

        // Inbox: three shares (§6).
        let shares: [(TimeInterval, InboxItem.Kind, String?, String?, String?, String?)] = [
            (-3 * 3600, .url, "Why local-first software wins", "https://example.com/local-first", nil, "For the Thursday call"),
            (-5 * 3600, .text, nil, nil, "Call the landlord about the deposit before Friday.", nil),
            (-8 * 3600, .image, "Whiteboard", nil, nil, "Sprint plan"),
        ]
        for (offset, kind, title, url, text, note) in shares {
            let stamp = now.addingTimeInterval(offset)
            let item = InboxItem(id: Ids.inbox(now: stamp), ts: RFC3339.string(stamp), kind: kind, title: title, url: url,
                                 text: text, file: nil, fromApp: kind == .url ? "com.apple.mobilesafari" : nil, note: note)
            try? await store.writeJSON(item, to: "inbox/\(item.id).json")
        }

        // App state.
        AppGroup.markCapture(.health, at: macRead)
        AppGroup.markCapture(.location, at: now.addingTimeInterval(-41 * 60))
        AppGroup.markCapture(.inbox, at: now.addingTimeInterval(-3 * 3600))
        AppGroup.defaults.set(true, forKey: "health.asked")
        UserDefaults.standard.set("Wrote \(records.count) health samples, 2 visits · \(TimeText.time(macRead))", forKey: "sync.lastLine")
        UserDefaults.standard.set(!forceWelcome, forKey: "welcome.done")
    }
}
#endif
