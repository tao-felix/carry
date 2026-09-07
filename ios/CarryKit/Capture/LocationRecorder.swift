import CoreLocation
import Foundation

/// Records visits and coarse points to `location/YYYY-MM-DD.jsonl` (DATA-CONTRACT §5). App target only.
/// Visits come from CLVisit; points from significant-location-change updates, at most one per 10 minutes.
public final class LocationRecorder: NSObject, ObservableObject, CLLocationManagerDelegate {
    public struct Written: Equatable {
        public var visits = 0
        public var points = 0
        public init() {}
    }

    public static let pointInterval: TimeInterval = 10 * 60

    @Published public private(set) var authorization: CLAuthorizationStatus = .notDetermined
    /// What was written since the last `syncNow()` report.
    @Published public private(set) var written = Written()

    /// Set by the app from `sources.json`; monitoring only runs while true.
    public var enabled = false

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private let defaults = AppGroup.defaults
    private var store: ContainerStore?
    private var wantsAlways = false
    private var oneShot: CheckedContinuation<Void, Never>?
    private var oneShotTimeout: Task<Void, Never>?

    public override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorization = manager.authorizationStatus
    }

    public func attach(_ store: ContainerStore) { self.store = store }

    // MARK: Authorization

    public var isAuthorized: Bool { authorization == .authorizedAlways || authorization == .authorizedWhenInUse }
    public var hasAsked: Bool { authorization != .notDetermined }

    /// Mono status for the Sources and Home screens.
    public var authorizationLabel: String {
        switch authorization {
        case .notDetermined: return "not asked yet"
        case .authorizedAlways: return "Always"
        case .authorizedWhenInUse: return "When in use · background needs Always"
        case .denied: return "denied · allow in Settings"
        case .restricted: return "restricted on this phone"
        @unknown default: return "unknown"
        }
    }

    public var needsAttention: Bool { authorization != .authorizedAlways }

    /// When-in-use first, then Always, as Apple requires.
    public func requestAuthorization() {
        wantsAlways = true
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse: manager.requestAlwaysAuthorization()
        default: break
        }
    }

    // MARK: Monitoring

    public func start() {
        guard enabled, isAuthorized else { return }
        manager.startMonitoringVisits()
        manager.startMonitoringSignificantLocationChanges()
    }

    public func stop() {
        manager.stopMonitoringVisits()
        manager.stopMonitoringSignificantLocationChanges()
    }

    /// For "Sync now": writes one fresh point if one is due, then reports what was written since the last report.
    public func syncNow() async -> Written {
        if enabled, isAuthorized, pointIsDue(Date()) {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                oneShot = continuation
                oneShotTimeout = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 8_000_000_000)
                    self?.finishOneShot()
                }
                manager.requestLocation()
            }
        }
        let report = written
        written = Written()
        return report
    }

    private func finishOneShot() {
        oneShotTimeout?.cancel()
        oneShotTimeout = nil
        oneShot?.resume()
        oneShot = nil
    }

    // MARK: CLLocationManagerDelegate

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        if wantsAlways, authorization == .authorizedWhenInUse {
            manager.requestAlwaysAuthorization()
        }
        if isAuthorized { start() }
    }

    public func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        let arrive = visit.arrivalDate == .distantPast ? nil : visit.arrivalDate
        let depart = visit.departureDate == .distantFuture ? nil : visit.departureDate
        let lat = visit.coordinate.latitude
        let lon = visit.coordinate.longitude
        let accuracy = Int(max(0, visit.horizontalAccuracy).rounded())
        Task { [weak self] in
            guard let self else { return }
            let place = await self.placeLabel(lat: lat, lon: lon)
            await self.write(.visit(arrive: arrive, depart: depart, lat: lat, lon: lon, accuracyM: accuracy, place: place))
            await MainActor.run { self.written.visits += 1 }
        }
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        defer { finishOneShot() }
        guard let location = locations.last, pointIsDue(location.timestamp) else { return }
        defaults.set(location.timestamp, forKey: "location.lastPoint")
        let record = LocationRecord.point(ts: location.timestamp, lat: location.coordinate.latitude,
                                          lon: location.coordinate.longitude,
                                          accuracyM: Int(max(0, location.horizontalAccuracy).rounded()))
        Task { [weak self] in
            guard let self else { return }
            await self.write(record)
            await MainActor.run { self.written.points += 1 }
        }
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finishOneShot()
    }

    // MARK: Helpers

    private func pointIsDue(_ at: Date) -> Bool {
        guard let last = defaults.object(forKey: "location.lastPoint") as? Date else { return true }
        return at.timeIntervalSince(last) >= Self.pointInterval
    }

    private func write(_ record: LocationRecord) async {
        guard let store else { return }
        try? await store.appendLocation(record)
        AppGroup.markCapture(.location)
    }

    /// Best-effort reverse geocode, cached by ~100 m cell so the same place is looked up once.
    private func placeLabel(lat: Double, lon: Double) async -> String? {
        let key = String(format: "%.3f,%.3f", lat, lon)
        var cache = defaults.dictionary(forKey: "location.geocache") as? [String: String] ?? [:]
        if let hit = cache[key] { return hit }
        guard let placemark = try? await geocoder.reverseGeocodeLocation(CLLocation(latitude: lat, longitude: lon)).first,
              let label = Self.label(placemark) else { return nil }
        if cache.count > 300 { cache.removeAll() }
        cache[key] = label
        defaults.set(cache, forKey: "location.geocache")
        return label
    }

    /// "Xuhui, Shanghai": the two most specific distinct parts.
    static func label(_ placemark: CLPlacemark) -> String? {
        var parts: [String] = []
        for part in [placemark.subLocality, placemark.locality, placemark.administrativeArea, placemark.country] {
            if let part, !part.isEmpty, !parts.contains(part) { parts.append(part) }
        }
        if parts.isEmpty, let name = placemark.name { parts.append(name) }
        return parts.isEmpty ? nil : parts.prefix(2).joined(separator: ", ")
    }
}
