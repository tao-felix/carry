import Foundation

// MARK: - sources.json (§3)

public struct SourceState: Codable, Equatable {
    public var enabled: Bool
    public var channel: Channel
    /// Health only: the enabled health types.
    public var types: [String]?

    public init(enabled: Bool, channel: Channel, types: [String]? = nil) {
        self.enabled = enabled
        self.channel = channel
        self.types = types
    }
}

public struct Processing: Codable, Equatable {
    public var ocr: Bool
    public var transcribe: Bool
}

public struct SourcesConfig: Codable, Equatable {
    public var schema: Int
    public var updatedAt: String
    public var sources: [String: SourceState]
    public var processing: Processing

    enum CodingKeys: String, CodingKey {
        case schema, sources, processing
        case updatedAt = "updated_at"
    }

    public static var defaults: SourcesConfig {
        var sources: [String: SourceState] = [:]
        for id in SourceID.allCases {
            sources[id.rawValue] = SourceState(
                enabled: id.defaultEnabled,
                channel: id.channel,
                types: id == .health ? HealthType.allCases.map(\.rawValue) : nil
            )
        }
        return SourcesConfig(schema: 1, updatedAt: RFC3339.string(Date()), sources: sources,
                             processing: Processing(ocr: true, transcribe: true))
    }

    public func isEnabled(_ id: SourceID) -> Bool { sources[id.rawValue]?.enabled ?? false }

    public var healthTypes: [HealthType] {
        (sources[SourceID.health.rawValue]?.types ?? []).compactMap(HealthType.init(rawValue:))
    }

    public mutating func setEnabled(_ id: SourceID, _ enabled: Bool) {
        var state = sources[id.rawValue] ?? SourceState(enabled: enabled, channel: id.channel)
        state.enabled = enabled
        state.channel = id.channel
        if id == .health, state.types == nil { state.types = HealthType.allCases.map(\.rawValue) }
        sources[id.rawValue] = state
    }

    public mutating func setHealthType(_ type: HealthType, _ enabled: Bool) {
        var state = sources[SourceID.health.rawValue] ?? SourceState(enabled: true, channel: .app, types: [])
        var types = state.types ?? []
        types.removeAll { $0 == type.rawValue }
        if enabled { types.append(type.rawValue) }
        // Keep the contract's canonical order.
        state.types = HealthType.allCases.map(\.rawValue).filter(types.contains)
        sources[SourceID.health.rawValue] = state
    }
}

// MARK: - manifest.json (§2)

public struct Manifest: Codable {
    public struct Device: Codable {
        public var name: String
        public var model: String
        public var os: String
        public init(name: String, model: String, os: String) {
            self.name = name; self.model = model; self.os = os
        }
    }
    public var schema = 1
    public var appVersion: String
    public var device: Device
    public var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case schema, device
        case appVersion = "app_version"
        case updatedAt = "updated_at"
    }

    public init(appVersion: String, device: Device, updatedAt: String = RFC3339.string(Date())) {
        self.appVersion = appVersion
        self.device = device
        self.updatedAt = updatedAt
    }
}

// MARK: - license.json (§7)

public struct License: Codable {
    public var schema = 1
    public var productId: String
    public var jws: String
    public var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case schema, jws
        case productId = "product_id"
        case updatedAt = "updated_at"
    }

    public init(productId: String, jws: String) {
        self.productId = productId
        self.jws = jws
        self.updatedAt = RFC3339.string(Date())
    }
}

// MARK: - heartbeat/<mac-host>.json (§8), written by the Mac

public struct Heartbeat: Decodable {
    public var host: String
    public var carryVersion: String?
    public var lastSyncAt: String
    public var lastDigestDate: String?
    public var counts: [String: Int]?
    public var pro: Bool?
    public var sourcesAppliedAt: String?

    enum CodingKeys: String, CodingKey {
        case host, counts, pro
        case carryVersion = "carry_version"
        case lastSyncAt = "last_sync_at"
        case lastDigestDate = "last_digest_date"
        case sourcesAppliedAt = "sources_applied_at"
    }

    public var lastSyncDate: Date? { RFC3339.date(lastSyncAt) }
}

// MARK: - health/YYYY-MM-DD.jsonl (§4)

public struct HealthRecord: Encodable {
    public enum Value: Encodable {
        case int(Int)
        case double(Double)
        case string(String)

        public func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            switch self {
            case .int(let v): try c.encode(v)
            case .double(let v): try c.encode(v)
            case .string(let v): try c.encode(v)
            }
        }
    }

    public var t: String
    public var start: Date
    public var end: Date
    public var v: Value
    public var u: String
    public var src: String
    public var meta: [String: Int]?

    public init(t: String, start: Date, end: Date, v: Value, u: String, src: String, meta: [String: Int]? = nil) {
        self.t = t; self.start = start; self.end = end; self.v = v; self.u = u; self.src = src; self.meta = meta
    }

    enum CodingKeys: String, CodingKey { case t, start, end, v, u, src, meta }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(t, forKey: .t)
        try c.encode(RFC3339.string(start), forKey: .start)
        try c.encode(RFC3339.string(end), forKey: .end)
        try c.encode(v, forKey: .v)
        try c.encode(u, forKey: .u)
        try c.encode(src, forKey: .src)
        try c.encodeIfPresent(meta, forKey: .meta)
    }
}

// MARK: - location/YYYY-MM-DD.jsonl (§5)

public enum LocationRecord: Encodable {
    /// `arrive`/`depart` are null when CoreLocation does not know them yet (an open visit).
    case visit(arrive: Date?, depart: Date?, lat: Double, lon: Double, accuracyM: Int, place: String?)
    case point(ts: Date, lat: Double, lon: Double, accuracyM: Int)

    /// The date used for the day bucket.
    public var bucketDate: Date {
        switch self {
        case .visit(let arrive, let depart, _, _, _, _): return arrive ?? depart ?? Date()
        case .point(let ts, _, _, _): return ts
        }
    }

    enum CodingKeys: String, CodingKey {
        case kind, arrive, depart, lat, lon, place, ts
        case accuracyM = "acc_m"
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .visit(let arrive, let depart, let lat, let lon, let acc, let place):
            try c.encode("visit", forKey: .kind)
            try c.encode(arrive.map(RFC3339.string), forKey: .arrive)
            try c.encode(depart.map(RFC3339.string), forKey: .depart)
            try c.encode(lat, forKey: .lat)
            try c.encode(lon, forKey: .lon)
            try c.encode(acc, forKey: .accuracyM)
            try c.encode(place, forKey: .place)
        case .point(let ts, let lat, let lon, let acc):
            try c.encode("point", forKey: .kind)
            try c.encode(RFC3339.string(ts), forKey: .ts)
            try c.encode(lat, forKey: .lat)
            try c.encode(lon, forKey: .lon)
            try c.encode(acc, forKey: .accuracyM)
        }
    }
}

// MARK: - inbox/<id>.json (§6)

public struct InboxItem: Codable {
    public enum Kind: String, Codable { case url, text, image, file }

    public var id: String
    public var ts: String
    public var kind: Kind
    public var title: String?
    public var url: String?
    public var text: String?
    public var file: String?
    public var fromApp: String?
    public var note: String?

    enum CodingKeys: String, CodingKey {
        case id, ts, kind, title, url, text, file, note
        case fromApp = "from_app"
    }

    public init(id: String, ts: String, kind: Kind, title: String?, url: String?, text: String?,
                file: String?, fromApp: String?, note: String?) {
        self.id = id; self.ts = ts; self.kind = kind; self.title = title; self.url = url
        self.text = text; self.file = file; self.fromApp = fromApp; self.note = note
    }

    /// Every key is present; absent values are written as null, as in the contract example.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(ts, forKey: .ts)
        try c.encode(kind, forKey: .kind)
        try c.encode(title, forKey: .title)
        try c.encode(url, forKey: .url)
        try c.encode(text, forKey: .text)
        try c.encode(file, forKey: .file)
        try c.encode(fromApp, forKey: .fromApp)
        try c.encode(note, forKey: .note)
    }
}
