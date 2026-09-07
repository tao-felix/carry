import Foundation

/// RFC 3339 timestamps with the device's UTC offset (never a bare "Z"), per DATA-CONTRACT.md §1.
public enum RFC3339 {
    /// `2026-09-07T21:30:00+08:00` in the current time zone.
    public static func string(_ date: Date) -> String {
        let zone = TimeZone.current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let offset = zone.secondsFromGMT(for: date)
        let sign = offset >= 0 ? "+" : "-"
        let magnitude = abs(offset)
        return String(
            format: "%04d-%02d-%02dT%02d:%02d:%02d%@%02d:%02d",
            c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!,
            sign, magnitude / 3600, (magnitude % 3600) / 60
        )
    }

    public static func date(_ string: String) -> Date? {
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: string) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: string)
    }
}

/// `YYYY-MM-DD` in the device's local calendar. JSONL day buckets use this.
public enum LocalDay {
    public static func string(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
}

/// Short relative time for mono status lines: "just now", "12 min ago", "3 h ago", "2 d ago".
public enum RelativeTime {
    public static func string(since date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min ago" }
        if seconds < 86_400 { return "\(Int(seconds / 3600)) h ago" }
        return "\(Int(seconds / 86_400)) d ago"
    }
}
