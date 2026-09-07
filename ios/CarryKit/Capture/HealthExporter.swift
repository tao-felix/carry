import Foundation
import HealthKit

/// Reads HealthKit incrementally and appends DATA-CONTRACT §4 records. App target only:
/// extensions cannot use HealthKit, and iOS refuses to read Health while the phone is locked.
/// `@unchecked`: mutable state (`observers`) is only touched from the main actor.
public final class HealthExporter: @unchecked Sendable {
    public struct Result: Equatable {
        public var samples = 0
        public var byType: [String: Int] = [:]
        public init() {}
    }

    public enum Failure: LocalizedError {
        case unavailable
        public var errorDescription: String? {
            switch self {
            case .unavailable: return "Health is not available on this device."
            }
        }
    }

    /// The first run reads this far back; later runs continue from the saved anchors.
    public static let backfillDays = 30
    /// Heart rate is thinned to the last sample in each window (§4).
    public static let heartRateWindow: TimeInterval = 5 * 60
    /// Completed hourly buckets are re-read this far back on every run: the Watch delivers late.
    /// The Mac dedupes by (type, start, end, src), so a re-written bucket replaces the old line.
    private static let bucketOverlap: TimeInterval = 2 * 3600

    public static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private let health = HKHealthStore()
    private let defaults = AppGroup.defaults
    private var observers: [HKObserverQuery] = []

    public init() {}

    // MARK: Authorization

    /// Apple hides read-authorization status, so the app remembers whether it asked.
    public var hasAsked: Bool { defaults.bool(forKey: "health.asked") }

    public func requestAuthorization(_ types: [HealthType] = HealthType.allCases) async throws {
        guard Self.isAvailable else { throw Failure.unavailable }
        try await health.requestAuthorization(toShare: [], read: Set(types.map(Self.objectType)))
        defaults.set(true, forKey: "health.asked")
    }

    // MARK: Export

    /// Appends every new sample for `types` and returns what was written.
    public func export(_ types: [HealthType], to store: ContainerStore, now: Date = Date()) async throws -> Result {
        guard Self.isAvailable else { throw Failure.unavailable }
        var result = Result()
        for type in types {
            let batch = try await read(type, now: now)
            if !batch.records.isEmpty {
                try await store.appendHealth(batch.records)
                result.samples += batch.records.count
                result.byType[type.rawValue] = batch.records.count
            }
            batch.commit()
        }
        AppGroup.markCapture(.health, at: now)
        return result
    }

    /// Forget anchors so the next export backfills again (after "Delete everything").
    public func resetAnchors() {
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix("health.anchor.") || key.hasPrefix("health.bucketEnd.") {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: Background delivery

    /// Asks HealthKit to wake the app (at most hourly) when these types change.
    /// `onChange` must call its completion when the export is done.
    public func enableBackgroundDelivery(_ types: [HealthType], onChange: @escaping (@escaping () -> Void) -> Void) {
        guard Self.isAvailable else { return }
        stopObservers()
        for type in types {
            guard let sampleType = Self.objectType(type) as? HKSampleType else { continue }
            health.enableBackgroundDelivery(for: sampleType, frequency: .hourly) { _, _ in }
            let query = HKObserverQuery(sampleType: sampleType, predicate: nil) { _, completion, error in
                // A failed observer (no entitlement, access revoked) must not trigger an export.
                guard error == nil else {
                    completion()
                    return
                }
                onChange(completion)
            }
            health.execute(query)
            observers.append(query)
        }
    }

    public func disableBackgroundDelivery() {
        guard Self.isAvailable else { return }
        stopObservers()
        health.disableAllBackgroundDelivery { _, _ in }
    }

    private func stopObservers() {
        for query in observers { health.stop(query) }
        observers.removeAll()
    }

    // MARK: Reading

    private struct Batch {
        var records: [HealthRecord]
        var commit: () -> Void
    }

    private static let bpm = HKUnit.count().unitDivided(by: .minute())

    private func read(_ type: HealthType, now: Date) async throws -> Batch {
        switch type {
        case .steps:
            return try await hourlyBuckets(.stepCount, unit: .count(), type: type, u: "count", now: now) {
                .int(Int($0.rounded()))
            }
        case .activeEnergy:
            return try await hourlyBuckets(.activeEnergyBurned, unit: .kilocalorie(), type: type, u: "kcal", now: now) {
                .double(($0 * 10).rounded() / 10)
            }
        case .heartRate:
            return try await quantitySamples(.heartRate, unit: Self.bpm, type: type, u: "bpm",
                                             window: Self.heartRateWindow, now: now) { .int(Int($0.rounded())) }
        case .restingHeartRate:
            return try await quantitySamples(.restingHeartRate, unit: Self.bpm, type: type, u: "bpm",
                                             window: nil, now: now) { .int(Int($0.rounded())) }
        case .hrv:
            return try await quantitySamples(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), type: type,
                                             u: "ms", window: nil, now: now) { .double(($0 * 10).rounded() / 10) }
        case .bodyMass:
            return try await quantitySamples(.bodyMass, unit: .gramUnit(with: .kilo), type: type, u: "kg",
                                             window: nil, now: now) { .double(($0 * 100).rounded() / 100) }
        case .bloodOxygen:
            // HKUnit.percent() yields a 0...1 fraction, which is the contract's "ratio".
            return try await quantitySamples(.oxygenSaturation, unit: .percent(), type: type, u: "ratio",
                                             window: nil, now: now) { .double(($0 * 1000).rounded() / 1000) }
        case .sleep:
            return try await sleep(now: now)
        case .workouts:
            return try await workouts(now: now)
        }
    }

    /// Steps and active energy: one line per completed hour (HKStatisticsCollectionQuery).
    private func hourlyBuckets(_ id: HKQuantityTypeIdentifier, unit: HKUnit, type: HealthType, u: String, now: Date,
                               value: @escaping (Double) -> HealthRecord.Value) async throws -> Batch {
        let quantityType = HKQuantityType(id)
        let key = "health.bucketEnd.\(type.rawValue)"
        let calendar = Calendar.current
        let endHour = Self.floorToHour(now, calendar)
        let earliest = now.addingTimeInterval(-Double(Self.backfillDays) * 86_400)
        let lastEnd = defaults.object(forKey: key) as? Date
        let from = lastEnd.map { max($0.addingTimeInterval(-Self.bucketOverlap), earliest) } ?? earliest
        let startHour = Self.floorToHour(from, calendar)
        guard startHour < endHour else { return Batch(records: [], commit: {}) }

        let predicate = HKQuery.predicateForSamples(withStart: startHour, end: endHour, options: .strictStartDate)
        let records: [HealthRecord] = try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(quantityType: quantityType, quantitySamplePredicate: predicate,
                                                    options: .cumulativeSum, anchorDate: endHour,
                                                    intervalComponents: DateComponents(hour: 1))
            query.initialResultsHandler = { _, collection, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                var out: [HealthRecord] = []
                collection?.enumerateStatistics(from: startHour, to: endHour) { stats, _ in
                    guard let sum = stats.sumQuantity() else { return }
                    let amount = sum.doubleValue(for: unit)
                    guard amount > 0 else { return }
                    out.append(HealthRecord(t: type.recordType, start: stats.startDate, end: stats.endDate,
                                            v: value(amount), u: u, src: "Health"))
                }
                continuation.resume(returning: out)
            }
            self.health.execute(query)
        }
        return Batch(records: records) { [defaults] in defaults.set(endHour, forKey: key) }
    }

    /// Raw quantity samples via an anchored query, optionally thinned to one per window.
    private func quantitySamples(_ id: HKQuantityTypeIdentifier, unit: HKUnit, type: HealthType, u: String,
                                 window: TimeInterval?, now: Date,
                                 value: @escaping (Double) -> HealthRecord.Value) async throws -> Batch {
        let (samples, commit) = try await anchored(HKQuantityType(id), key: type.rawValue, now: now)
        var quantities = samples.compactMap { $0 as? HKQuantitySample }
        if let window {
            // Keep the last sample in each window.
            var byWindow: [Int: HKQuantitySample] = [:]
            for sample in quantities {
                let slot = Int(sample.startDate.timeIntervalSince1970 / window)
                if let kept = byWindow[slot], kept.startDate > sample.startDate { continue }
                byWindow[slot] = sample
            }
            quantities = byWindow.values.sorted { $0.startDate < $1.startDate }
        }
        let records = quantities.map { sample in
            HealthRecord(t: type.recordType, start: sample.startDate, end: sample.endDate,
                         v: value(sample.quantity.doubleValue(for: unit)), u: u,
                         src: sample.sourceRevision.source.name)
        }
        return Batch(records: records, commit: commit)
    }

    private func sleep(now: Date) async throws -> Batch {
        let (samples, commit) = try await anchored(HKCategoryType(.sleepAnalysis), key: "sleep", now: now)
        let records = samples.compactMap { $0 as? HKCategorySample }.compactMap { sample -> HealthRecord? in
            guard let stage = Self.sleepStage(sample.value) else { return nil }
            return HealthRecord(t: "sleep", start: sample.startDate, end: sample.endDate, v: .string(stage),
                                u: "stage", src: sample.sourceRevision.source.name)
        }
        return Batch(records: records, commit: commit)
    }

    private func workouts(now: Date) async throws -> Batch {
        let (samples, commit) = try await anchored(HKWorkoutType.workoutType(), key: "workouts", now: now)
        let records = samples.compactMap { $0 as? HKWorkout }.map { workout -> HealthRecord in
            var meta: [String: Int] = [:]
            if let meters = Self.distanceMeters(workout) { meta["distance_m"] = Int(meters.rounded()) }
            if let kcal = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?
                .doubleValue(for: .kilocalorie()), kcal > 0 {
                meta["energy_kcal"] = Int(kcal.rounded())
            }
            return HealthRecord(t: "workout", start: workout.startDate, end: workout.endDate,
                                v: .string(Self.activityName(workout.workoutActivityType)), u: "type",
                                src: workout.sourceRevision.source.name, meta: meta.isEmpty ? nil : meta)
        }
        return Batch(records: records, commit: commit)
    }

    /// Runs an anchored query. The returned closure saves the new anchor; call it after the records are on disk.
    private func anchored(_ sampleType: HKSampleType, key: String, now: Date) async throws -> ([HKSample], () -> Void) {
        let anchorKey = "health.anchor.\(key)"
        let anchor = loadAnchor(anchorKey)
        let predicate = anchor == nil
            ? HKQuery.predicateForSamples(withStart: now.addingTimeInterval(-Double(Self.backfillDays) * 86_400),
                                          end: nil)
            : nil
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(type: sampleType, predicate: predicate, anchor: anchor,
                                              limit: HKObjectQueryNoLimit) { _, samples, _, newAnchor, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let commit = { [weak self] in
                    if let newAnchor { self?.saveAnchor(newAnchor, anchorKey) }
                }
                continuation.resume(returning: (samples ?? [], commit))
            }
            self.health.execute(query)
        }
    }

    // MARK: Anchors

    private func loadAnchor(_ key: String) -> HKQueryAnchor? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    private func saveAnchor(_ anchor: HKQueryAnchor, _ key: String) {
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true) {
            defaults.set(data, forKey: key)
        }
    }

    // MARK: Mapping

    static func objectType(_ type: HealthType) -> HKObjectType {
        switch type {
        case .sleep: return HKCategoryType(.sleepAnalysis)
        case .steps: return HKQuantityType(.stepCount)
        case .heartRate: return HKQuantityType(.heartRate)
        case .restingHeartRate: return HKQuantityType(.restingHeartRate)
        case .hrv: return HKQuantityType(.heartRateVariabilitySDNN)
        case .activeEnergy: return HKQuantityType(.activeEnergyBurned)
        case .workouts: return HKWorkoutType.workoutType()
        case .bodyMass: return HKQuantityType(.bodyMass)
        case .bloodOxygen: return HKQuantityType(.oxygenSaturation)
        }
    }

    /// Contract stages: inBed, asleepUnspecified, awake, core, deep, rem.
    static func sleepStage(_ raw: Int) -> String? {
        switch HKCategoryValueSleepAnalysis(rawValue: raw) {
        case .inBed: return "inBed"
        case .asleepUnspecified: return "asleepUnspecified"
        case .awake: return "awake"
        case .asleepCore: return "core"
        case .asleepDeep: return "deep"
        case .asleepREM: return "rem"
        default: return nil
        }
    }

    private static let distanceTypes: [HKQuantityTypeIdentifier] = [
        .distanceWalkingRunning, .distanceCycling, .distanceSwimming, .distanceWheelchair, .distanceDownhillSnowSports,
    ]

    static func distanceMeters(_ workout: HKWorkout) -> Double? {
        for id in distanceTypes {
            if let meters = workout.statistics(for: HKQuantityType(id))?.sumQuantity()?.doubleValue(for: .meter()),
               meters > 0 {
                return meters
            }
        }
        return nil
    }

    static func activityName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: return "running"
        case .walking: return "walking"
        case .cycling: return "cycling"
        case .swimming: return "swimming"
        case .hiking: return "hiking"
        case .yoga: return "yoga"
        case .functionalStrengthTraining, .traditionalStrengthTraining: return "strength"
        case .highIntensityIntervalTraining: return "hiit"
        case .elliptical: return "elliptical"
        case .rowing: return "rowing"
        case .stairClimbing: return "stairs"
        case .coreTraining: return "core"
        case .pilates: return "pilates"
        case .dance, .cardioDance, .socialDance: return "dance"
        case .tennis: return "tennis"
        case .tableTennis: return "table_tennis"
        case .badminton: return "badminton"
        case .soccer: return "soccer"
        case .basketball: return "basketball"
        case .golf: return "golf"
        case .cooldown: return "cooldown"
        case .mindAndBody: return "mind_and_body"
        case .mixedCardio: return "mixed_cardio"
        default: return "other_\(type.rawValue)"
        }
    }

    static func floorToHour(_ date: Date, _ calendar: Calendar) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month, .day, .hour], from: date)) ?? date
    }
}
