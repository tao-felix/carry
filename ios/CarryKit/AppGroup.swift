import Foundation

/// UserDefaults shared by the app and the share extension (anchors, capture times, caches).
public enum AppGroup {
    public static let identifier = "group.app.carry"

    public static let defaults: UserDefaults = UserDefaults(suiteName: identifier) ?? .standard

    private static func captureKey(_ source: SourceID) -> String { "capture.last.\(source.rawValue)" }

    /// Remember when a source last wrote something, for the Home screen.
    public static func markCapture(_ source: SourceID, at date: Date = Date()) {
        defaults.set(date, forKey: captureKey(source))
    }

    public static func lastCapture(_ source: SourceID) -> Date? {
        defaults.object(forKey: captureKey(source)) as? Date
    }

    public static func clearCapture(_ source: SourceID) {
        defaults.removeObject(forKey: captureKey(source))
    }
}
