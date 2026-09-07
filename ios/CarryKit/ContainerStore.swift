import Foundation

/// Where Carry's files live. The iCloud container is the whole backend (DATA-CONTRACT.md §1).
public enum ContainerLocation: Equatable, Sendable {
    case icloud(URL)
    /// DEBUG only: a local folder so every screen works in a simulator without iCloud.
    case debugFallback(URL)

    /// The `Documents/` folder every path in the contract is relative to.
    public var documents: URL {
        switch self {
        case .icloud(let url), .debugFallback(let url): return url
        }
    }

    public var isICloud: Bool {
        if case .icloud = self { return true }
        return false
    }
}

/// Coordinated, append-only access to the container. All paths are relative to `Documents/`.
public actor ContainerStore {
    public static let ubiquityContainerID = "iCloud.app.carry.ios"
    public static let folders = ["health", "location", "inbox", "heartbeat"]

    public let location: ContainerLocation
    private let coordinator = NSFileCoordinator(filePresenter: nil)
    private let fileManager = FileManager.default

    /// Resolves the container. Slow on first call; never call on the main thread.
    /// Returns nil when iCloud Drive is off for Carry (release builds).
    public nonisolated static func resolve() -> ContainerLocation? {
        if let url = FileManager.default.url(forUbiquityContainerIdentifier: ubiquityContainerID) {
            return .icloud(url.appendingPathComponent("Documents", isDirectory: true))
        }
        #if DEBUG
        // The app group so the app and the share extension see the same files in the simulator.
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return .debugFallback(base.appendingPathComponent("CarryContainer/Documents", isDirectory: true))
        #else
        return nil
        #endif
    }

    public init(location: ContainerLocation) {
        self.location = location
    }

    // MARK: Layout

    public func ensureLayout() throws {
        let root = location.documents
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        for folder in Self.folders {
            try fileManager.createDirectory(at: root.appendingPathComponent(folder, isDirectory: true),
                                            withIntermediateDirectories: true)
        }
    }

    public nonisolated func url(_ relativePath: String) -> URL {
        location.documents.appendingPathComponent(relativePath)
    }

    // MARK: Primitives

    private static let jsonEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }()

    private static let lineEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }()

    /// Replace-whole write: encode, then atomically replace the file under coordination.
    public func writeJSON<T: Encodable>(_ value: T, to relativePath: String) throws {
        let data = try Self.jsonEncoder.encode(value)
        try writeData(data, to: relativePath)
    }

    public func writeData(_ data: Data, to relativePath: String) throws {
        try coordinatedWrite(url(relativePath), options: .forReplacing) { target in
            try data.write(to: target, options: .atomic)
        }
    }

    public func copyFile(from source: URL, to relativePath: String) throws {
        try coordinatedWrite(url(relativePath), options: .forReplacing) { target in
            if self.fileManager.fileExists(atPath: target.path) { try self.fileManager.removeItem(at: target) }
            try self.fileManager.copyItem(at: source, to: target)
        }
    }

    public func readJSON<T: Decodable>(_ type: T.Type, at relativePath: String) throws -> T? {
        guard let data = try readData(at: relativePath) else { return nil }
        return try JSONDecoder().decode(type, from: data)
    }

    public func readData(at relativePath: String) throws -> Data? {
        let target = url(relativePath)
        guard fileManager.fileExists(atPath: target.path) else { return nil }
        var data: Data?
        try coordinatedRead(target) { data = try Data(contentsOf: $0) }
        return data
    }

    /// Append-only: JSONL files are never rewritten in place.
    public func appendLines<T: Encodable>(_ values: [T], to relativePath: String) throws {
        guard !values.isEmpty else { return }
        var payload = Data()
        for value in values {
            payload.append(try Self.lineEncoder.encode(value))
            payload.append(0x0A)
        }
        try coordinatedWrite(url(relativePath), options: .forMerging) { target in
            if !self.fileManager.fileExists(atPath: target.path) {
                self.fileManager.createFile(atPath: target.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: target)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: payload)
        }
    }

    public func remove(_ relativePath: String) throws {
        let target = url(relativePath)
        guard fileManager.fileExists(atPath: target.path) else { return }
        try coordinatedWrite(target, options: .forDeleting) { try self.fileManager.removeItem(at: $0) }
    }

    /// Deletes everything Carry wrote, then recreates the empty layout.
    public func deleteEverything() throws {
        let root = location.documents
        try coordinatedWrite(root, options: .forDeleting) { target in
            for child in try self.fileManager.contentsOfDirectory(at: target, includingPropertiesForKeys: nil) {
                try self.fileManager.removeItem(at: child)
            }
        }
        try ensureLayout()
    }

    // MARK: Contract files

    public func readSources() -> SourcesConfig? {
        try? readJSON(SourcesConfig.self, at: "sources.json")
    }

    public func writeSources(_ config: SourcesConfig) throws {
        var stamped = config
        stamped.updatedAt = RFC3339.string(Date())
        try writeJSON(stamped, to: "sources.json")
    }

    public func writeManifest(_ manifest: Manifest) throws {
        try writeJSON(manifest, to: "manifest.json")
    }

    public func writeLicense(_ license: License) throws {
        try writeJSON(license, to: "license.json")
    }

    public func removeLicense() throws {
        try remove("license.json")
    }

    /// Groups records by the local day of `start` and appends to `health/YYYY-MM-DD.jsonl`.
    public func appendHealth(_ records: [HealthRecord]) throws {
        let byDay = Dictionary(grouping: records) { LocalDay.string($0.start) }
        for (day, group) in byDay.sorted(by: { $0.key < $1.key }) {
            try appendLines(group, to: "health/\(day).jsonl")
        }
    }

    public func appendLocation(_ record: LocationRecord) throws {
        try appendLines([record], to: "location/\(LocalDay.string(record.bucketDate)).jsonl")
    }

    /// Newest heartbeat across Macs. iCloud placeholders are queued for download and skipped.
    public func latestHeartbeat() -> Heartbeat? {
        let dir = url("heartbeat")
        guard let entries = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return nil
        }
        var newest: Heartbeat?
        for entry in entries {
            let name = entry.lastPathComponent
            if name.hasPrefix("."), name.hasSuffix(".icloud") {
                let real = dir.appendingPathComponent(String(name.dropFirst().dropLast(".icloud".count)))
                try? fileManager.startDownloadingUbiquitousItem(at: real)
                continue
            }
            guard entry.pathExtension == "json",
                  let data = try? readData(at: "heartbeat/\(name)"),
                  let beat = try? JSONDecoder().decode(Heartbeat.self, from: data) else { continue }
            if let current = newest, (current.lastSyncDate ?? .distantPast) >= (beat.lastSyncDate ?? .distantPast) {
                continue
            }
            newest = beat
        }
        return newest
    }

    /// What the app wrote today, for the Home screen.
    public struct TodayCounts: Equatable {
        public var health = 0
        public var visits = 0
        public var points = 0
        public var inbox = 0
    }

    public func todayCounts(now: Date = Date()) -> TodayCounts {
        let day = LocalDay.string(now)
        var counts = TodayCounts()
        if let data = try? readData(at: "health/\(day).jsonl") {
            counts.health = data.reduce(0) { $0 + ($1 == 0x0A ? 1 : 0) }
        }
        if let data = try? readData(at: "location/\(day).jsonl"), let text = String(data: data, encoding: .utf8) {
            for line in text.split(separator: "\n") {
                if line.contains("\"kind\":\"visit\"") { counts.visits += 1 }
                if line.contains("\"kind\":\"point\"") { counts.points += 1 }
            }
        }
        if let entries = try? fileManager.contentsOfDirectory(at: url("inbox"), includingPropertiesForKeys: nil) {
            for entry in entries where entry.pathExtension == "json" {
                guard let item = try? readJSON(InboxItem.self, at: "inbox/\(entry.lastPathComponent)"),
                      let ts = RFC3339.date(item.ts) else { continue }
                if LocalDay.string(ts) == day { counts.inbox += 1 }
            }
        }
        return counts
    }

    // MARK: Coordination

    private func coordinatedWrite(_ target: URL, options: NSFileCoordinator.WritingOptions,
                                  _ body: (URL) throws -> Void) throws {
        var coordinationError: NSError?
        var bodyError: Error?
        coordinator.coordinate(writingItemAt: target, options: options, error: &coordinationError) { url in
            do { try body(url) } catch { bodyError = error }
        }
        if let coordinationError { throw coordinationError }
        if let bodyError { throw bodyError }
    }

    private func coordinatedRead(_ target: URL, _ body: (URL) throws -> Void) throws {
        var coordinationError: NSError?
        var bodyError: Error?
        coordinator.coordinate(readingItemAt: target, options: .withoutChanges, error: &coordinationError) { url in
            do { try body(url) } catch { bodyError = error }
        }
        if let coordinationError { throw coordinationError }
        if let bodyError { throw bodyError }
    }
}
