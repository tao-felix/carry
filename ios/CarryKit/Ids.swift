import Foundation

public enum Ids {
    private static let base32 = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    /// Inbox id per DATA-CONTRACT.md §6: `YYYYMMDDTHHmmssZ-<6 random base32 chars>` (UTC stamp).
    public static func inbox(now: Date = Date()) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: now)
        let stamp = String(format: "%04d%02d%02dT%02d%02d%02dZ", c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!)
        let suffix = String((0..<6).map { _ in base32.randomElement()! })
        return "\(stamp)-\(suffix)"
    }
}
