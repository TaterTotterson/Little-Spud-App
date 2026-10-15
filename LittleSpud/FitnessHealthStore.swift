import Foundation
import HealthKit
import CryptoKit

extension Notification.Name {
    static let littleSpudFitnessHealthChanged = Notification.Name("littleSpudFitnessHealthChanged")
}

struct FitnessHealthSyncPlan {
    var days: [LittleSpudFitnessDay]
    var completedFullReconciliation: Bool
}

final class FitnessHealthStore {
    static let shared = FitnessHealthStore()
    static let syncEnabledKey = "little-spud-ios:fitness-sync-enabled"

    private let store = HKHealthStore()
    private let syncHistoryLock = NSLock()
    private let backgroundSyncLock = NSLock()
    private var observers: [HKObserverQuery] = []
    private var backgroundSyncRunning = false
    private var backgroundSyncCompletions: [() -> Void] = []

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }
    var syncEnabled: Bool { UserDefaults.standard.bool(forKey: Self.syncEnabledKey) }

    func coreAvailable(session: LittleSpudSession) -> Bool {
        UserDefaults.standard.bool(forKey: coreAvailabilityKey(scope: syncScope(session)))
    }

    func setCoreAvailable(_ available: Bool, session: LittleSpudSession) {
        UserDefaults.standard.set(available, forKey: coreAvailabilityKey(scope: syncScope(session)))
        if available {
            startBackgroundObservers()
        } else {
            stopBackgroundObservers()
        }
    }

    private var quantityTypes: [(HKQuantityType, HKStatisticsOptions, HKUnit, String, Double)] {
        var rows: [(HKQuantityType, HKStatisticsOptions, HKUnit, String, Double)] = []
        func add(
            _ id: HKQuantityTypeIdentifier,
            _ options: HKStatisticsOptions,
            _ unit: HKUnit,
            _ key: String,
            multiplier: Double = 1
        ) {
            if let type = HKObjectType.quantityType(forIdentifier: id) {
                rows.append((type, options, unit, key, multiplier))
            }
        }
        add(.stepCount, .cumulativeSum, .count(), "steps")
        add(.distanceWalkingRunning, .cumulativeSum, .meter(), "distance")
        add(.activeEnergyBurned, .cumulativeSum, .kilocalorie(), "energy")
        add(.appleExerciseTime, .cumulativeSum, .minute(), "exercise")
        let beatsPerMinute = HKUnit.count().unitDivided(by: .minute())
        add(.heartRate, .discreteAverage, beatsPerMinute, "heartRateAverage")
        add(.heartRate, .discreteMin, beatsPerMinute, "heartRateMinimum")
        add(.heartRate, .discreteMax, beatsPerMinute, "heartRateMaximum")
        add(.restingHeartRate, .discreteAverage, HKUnit.count().unitDivided(by: .minute()), "restingHeartRate")
        add(.heartRateVariabilitySDNN, .discreteAverage, HKUnit.secondUnit(with: .milli), "heartRateVariability")
        add(.bloodPressureSystolic, .discreteAverage, .millimeterOfMercury(), "bloodPressureSystolic")
        add(.bloodPressureDiastolic, .discreteAverage, .millimeterOfMercury(), "bloodPressureDiastolic")
        add(.oxygenSaturation, .discreteAverage, .percent(), "oxygenSaturationPercent", multiplier: 100)
        add(.respiratoryRate, .discreteAverage, HKUnit.count().unitDivided(by: .minute()), "respiratoryRate")
        add(.bodyMass, .discreteAverage, .gramUnit(with: .kilo), "weight")
        add(.bodyFatPercentage, .discreteAverage, .percent(), "bodyFatPercent", multiplier: 100)
        return rows
    }

    private var readTypes: Set<HKObjectType> {
        var values = Set<HKObjectType>(quantityTypes.map(\.0))
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { values.insert(sleep) }
        values.insert(HKObjectType.workoutType())
        return values
    }

    func requestAccess() async throws {
        guard isAvailable else { throw FitnessHealthError.unavailable }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.requestAuthorization(toShare: [], read: readTypes) { success, error in
                if let error { continuation.resume(throwing: error) }
                else if success { continuation.resume() }
                else { continuation.resume(throwing: FitnessHealthError.authorizationDenied) }
            }
        }
        UserDefaults.standard.set(true, forKey: Self.syncEnabledKey)
        startBackgroundObservers(refresh: true)
    }

    func prepareForSync(requestIfNeeded: Bool) async throws -> Bool {
        guard isAvailable else { throw FitnessHealthError.unavailable }
        let status = try await authorizationRequestStatus()
        switch status {
        case .shouldRequest:
            guard requestIfNeeded else { return false }
            try await requestAccess()
            return true
        case .unnecessary:
            startBackgroundObservers()
            return true
        case .unknown:
            return false
        @unknown default:
            return false
        }
    }

    func isAuthorizationPending(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.localizedDescription.localizedCaseInsensitiveContains("authorization not determined")
            || nsError.localizedFailureReason?.localizedCaseInsensitiveContains("authorization not determined") == true
    }

    private func authorizationRequestStatus() async throws -> HKAuthorizationRequestStatus {
        try await withCheckedThrowingContinuation { continuation in
            store.getRequestStatusForAuthorization(toShare: [], read: readTypes) { status, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: status) }
            }
        }
    }

    func startBackgroundObservers(refresh: Bool = false) {
        if refresh {
            stopBackgroundObservers()
        }
        guard isAvailable,
              syncEnabled,
              observers.isEmpty,
              let session = (try? KeychainStore.load(LittleSpudSession.self, account: "little-spud-session")) ?? nil,
              !session.isDemo,
              coreAvailable(session: session) else { return }
        let types = readTypes.compactMap { $0 as? HKSampleType }
        for type in types {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, error in
                guard error == nil else { completion(); return }
                self.enqueueBackgroundSync(completion: completion)
            }
            observers.append(query)
            store.execute(query)
            store.enableBackgroundDelivery(for: type, frequency: .hourly) { _, _ in }
        }
    }

    private func stopBackgroundObservers() {
        observers.forEach(store.stop)
        observers.removeAll()
    }

    private func enqueueBackgroundSync(completion: @escaping () -> Void) {
        backgroundSyncLock.lock()
        backgroundSyncCompletions.append(completion)
        guard !backgroundSyncRunning else {
            backgroundSyncLock.unlock()
            return
        }
        backgroundSyncRunning = true
        backgroundSyncLock.unlock()

        Task {
            while true {
                let completions = takeBackgroundSyncCompletions()
                try? await syncDailyTotalsToTater()
                await MainActor.run {
                    NotificationCenter.default.post(name: .littleSpudFitnessHealthChanged, object: nil)
                    completions.forEach { $0() }
                }
                if !prepareNextBackgroundSyncBatch() { break }
            }
        }
    }

    private func takeBackgroundSyncCompletions() -> [() -> Void] {
        backgroundSyncLock.lock()
        defer { backgroundSyncLock.unlock() }
        let completions = backgroundSyncCompletions
        backgroundSyncCompletions.removeAll()
        return completions
    }

    private func prepareNextBackgroundSyncBatch() -> Bool {
        backgroundSyncLock.lock()
        defer { backgroundSyncLock.unlock() }
        if backgroundSyncCompletions.isEmpty {
            backgroundSyncRunning = false
            return false
        }
        return true
    }

    private func syncDailyTotalsToTater() async throws {
        guard syncEnabled,
              let session = try KeychainStore.load(LittleSpudSession.self, account: "little-spud-session"),
              !session.isDemo,
              coreAvailable(session: session) else { return }
        do {
            _ = try await SpudLinkAPI().fetchFitness(session: session, refresh: false)
            setCoreAvailable(true, session: session)
        } catch {
            if Self.isCoreUnavailable(error) {
                setCoreAvailable(false, session: session)
                return
            }
            throw error
        }
        guard try await prepareForSync(requestIfNeeded: false) else { return }
        let plan = try await pendingDailyTotals(session: session)
        if !plan.days.isEmpty {
            _ = try await SpudLinkAPI().syncFitness(
                session: session,
                platform: "ios-healthkit",
                timeZone: TimeZone.autoupdatingCurrent.identifier,
                permissions: Self.permissionNames,
                days: plan.days
            )
        }
        markDailyTotalsSynced(plan, session: session)
    }

    func pendingDailyTotals(session: LittleSpudSession) async throws -> FitnessHealthSyncPlan {
        let scope = syncScope(session)
        let today = Self.currentDayString()
        let cached = syncFingerprints(scope: scope)
        let fullReconciliation = cached.isEmpty || UserDefaults.standard.string(
            forKey: fullReconciliationKey(scope: scope)
        ) != today
        let candidates = try await fetchDailyTotals(days: fullReconciliation ? 30 : 2)
        let changed = candidates.filter { cached[$0.date] != Self.fingerprint($0) }
        return FitnessHealthSyncPlan(days: changed, completedFullReconciliation: fullReconciliation)
    }

    func markDailyTotalsSynced(_ plan: FitnessHealthSyncPlan, session: LittleSpudSession) {
        let scope = syncScope(session)
        syncHistoryLock.lock()
        defer { syncHistoryLock.unlock() }
        var cached = UserDefaults.standard.dictionary(forKey: fingerprintsKey(scope: scope)) as? [String: String] ?? [:]
        for day in plan.days {
            cached[day.date] = Self.fingerprint(day)
        }
        let retained = Dictionary(uniqueKeysWithValues: cached.keys.sorted(by: >).prefix(120).compactMap { key in
            cached[key].map { (key, $0) }
        })
        UserDefaults.standard.set(retained, forKey: fingerprintsKey(scope: scope))
        if plan.completedFullReconciliation {
            UserDefaults.standard.set(
                Self.currentDayString(),
                forKey: fullReconciliationKey(scope: scope)
            )
        }
    }

    func resetSyncHistory(session: LittleSpudSession) {
        let scope = syncScope(session)
        UserDefaults.standard.removeObject(forKey: fingerprintsKey(scope: scope))
        UserDefaults.standard.removeObject(forKey: fullReconciliationKey(scope: scope))
    }

    private func syncFingerprints(scope: String) -> [String: String] {
        syncHistoryLock.lock()
        defer { syncHistoryLock.unlock() }
        return UserDefaults.standard.dictionary(forKey: fingerprintsKey(scope: scope)) as? [String: String] ?? [:]
    }

    private func syncScope(_ session: LittleSpudSession) -> String {
        SHA256.hash(data: Data("\(session.hubUrl)|\(session.token)".utf8))
            .map { String(format: "%02x", $0) }
            .joined()
            .prefix(20)
            .description
    }

    private func fingerprintsKey(scope: String) -> String {
        "little-spud-ios:fitness-fingerprints:\(scope)"
    }

    private func fullReconciliationKey(scope: String) -> String {
        "little-spud-ios:fitness-full-day:\(scope)"
    }

    private func coreAvailabilityKey(scope: String) -> String {
        "little-spud-ios:fitness-core-available:\(scope)"
    }

    static func isCoreUnavailable(_ error: Error) -> Bool {
        guard let apiError = error as? SpudLinkAPIError,
              apiError.statusCode == 404 || apiError.statusCode == 409 else { return false }
        return !error.localizedDescription.localizedCaseInsensitiveContains("link little spud")
    }

    private static func currentDayString() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    static let permissionNames = [
        "steps", "distance", "active_energy", "exercise", "workouts", "sleep", "heart_rate",
        "resting_heart_rate", "heart_rate_variability", "blood_pressure", "oxygen_saturation",
        "respiratory_rate", "weight", "body_fat"
    ]

    private static func fingerprint(_ day: LittleSpudFitnessDay) -> String {
        func number(_ value: Double?) -> String {
            value.map { String(format: "%.5f", locale: Locale(identifier: "en_US_POSIX"), $0) } ?? "-"
        }
        let values = [
            day.date,
            day.steps.map(String.init) ?? "-",
            number(day.distanceMeters), number(day.activeEnergyKcal), number(day.exerciseMinutes),
            day.workouts.map(String.init) ?? "-",
            number(day.sleepMinutes), number(day.sleepCoreMinutes), number(day.sleepDeepMinutes),
            number(day.sleepREMMinutes), number(day.sleepAwakeMinutes), number(day.heartRateAverage),
            number(day.heartRateMinimum), number(day.heartRateMaximum), number(day.restingHeartRate),
            number(day.heartRateVariability), number(day.bloodPressureSystolic),
            number(day.bloodPressureDiastolic), number(day.oxygenSaturationPercent),
            number(day.respiratoryRate), number(day.weightKilograms), number(day.bodyFatPercent)
        ]
        return SHA256.hash(data: Data(values.joined(separator: "|").utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    func fetchDailyTotals(days count: Int = 30) async throws -> [LittleSpudFitnessDay] {
        guard isAvailable else { throw FitnessHealthError.unavailable }
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -(max(1, count) - 1), to: today),
              let end = calendar.date(byAdding: .day, value: 1, to: today) else { return [] }

        var values: [Date: FitnessDayValues] = [:]
        for (type, options, unit, key, multiplier) in quantityTypes {
            let rows = try await statistics(
                type: type,
                options: options,
                unit: unit,
                multiplier: multiplier,
                start: start,
                end: end
            )
            for (day, value) in rows {
                var current = values[day] ?? FitnessDayValues()
                current.set(key: key, value: value)
                values[day] = current
            }
        }
        let sleep = try await sleepValues(start: start, end: end)
        let workouts = try await workoutCounts(start: start, end: end)
        var output: [LittleSpudFitnessDay] = []
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        for offset in 0..<max(1, count) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let row = values[day] ?? FitnessDayValues()
            let sleepRow = sleep[day]
            output.append(
                LittleSpudFitnessDay(
                    date: formatter.string(from: day),
                    steps: positive(row.steps).map { Int($0.rounded()) },
                    distanceMeters: positive(row.distance),
                    activeEnergyKcal: positive(row.energy),
                    exerciseMinutes: positive(row.exercise),
                    workouts: workouts[day].flatMap { $0 > 0 ? $0 : nil },
                    sleepMinutes: positive(sleepRow?.totalMinutes),
                    sleepCoreMinutes: positive(sleepRow?.coreMinutes),
                    sleepDeepMinutes: positive(sleepRow?.deepMinutes),
                    sleepREMMinutes: positive(sleepRow?.remMinutes),
                    sleepAwakeMinutes: positive(sleepRow?.awakeMinutes),
                    heartRateAverage: positive(row.heartRateAverage),
                    heartRateMinimum: positive(row.heartRateMinimum),
                    heartRateMaximum: positive(row.heartRateMaximum),
                    restingHeartRate: positive(row.restingHeartRate),
                    heartRateVariability: positive(row.heartRateVariability),
                    bloodPressureSystolic: positive(row.bloodPressureSystolic),
                    bloodPressureDiastolic: positive(row.bloodPressureDiastolic),
                    oxygenSaturationPercent: positive(row.oxygenSaturationPercent),
                    respiratoryRate: positive(row.respiratoryRate),
                    weightKilograms: positive(row.weight),
                    bodyFatPercent: positive(row.bodyFatPercent)
                )
            )
        }
        return output
    }

    private func positive(_ value: Double?) -> Double? {
        guard let value, value > 0 else { return nil }
        return value
    }

    private func statistics(
        type: HKQuantityType,
        options: HKStatisticsOptions,
        unit: HKUnit,
        multiplier: Double,
        start: Date,
        end: Date
    ) async throws -> [Date: Double] {
        try await withCheckedThrowingContinuation { continuation in
            let calendar = Calendar.autoupdatingCurrent
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: options,
                anchorDate: calendar.startOfDay(for: start),
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, collection, error in
                if let error { continuation.resume(throwing: error); return }
                var result: [Date: Double] = [:]
                collection?.enumerateStatistics(from: start, to: end) { statistic, _ in
                    let quantity: HKQuantity?
                    if options.contains(.cumulativeSum) {
                        quantity = statistic.sumQuantity()
                    } else if options.contains(.discreteMin) {
                        quantity = statistic.minimumQuantity()
                    } else if options.contains(.discreteMax) {
                        quantity = statistic.maximumQuantity()
                    } else {
                        quantity = statistic.averageQuantity()
                    }
                    guard let quantity else { return }
                    result[calendar.startOfDay(for: statistic.startDate)] = quantity.doubleValue(for: unit) * multiplier
                }
                continuation.resume(returning: result)
            }
            store.execute(query)
        }
    }

    private func sleepValues(start: Date, end: Date) async throws -> [Date: SleepDayValues] {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return [:] }
        let samples: [HKCategorySample] = try await samples(type: type, start: start, end: end)
        let calendar = Calendar.autoupdatingCurrent
        var result: [Date: SleepDayValues] = [:]
        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
        ]
        for sample in samples {
            let day = calendar.startOfDay(for: sample.endDate)
            let minutes = max(0, sample.endDate.timeIntervalSince(sample.startDate) / 60)
            var row = result[day] ?? SleepDayValues()
            if asleepValues.contains(sample.value) { row.totalMinutes += minutes }
            switch sample.value {
            case HKCategoryValueSleepAnalysis.asleepCore.rawValue: row.coreMinutes += minutes
            case HKCategoryValueSleepAnalysis.asleepDeep.rawValue: row.deepMinutes += minutes
            case HKCategoryValueSleepAnalysis.asleepREM.rawValue: row.remMinutes += minutes
            case HKCategoryValueSleepAnalysis.awake.rawValue: row.awakeMinutes += minutes
            default: break
            }
            result[day] = row
        }
        return result
    }

    private func workoutCounts(start: Date, end: Date) async throws -> [Date: Int] {
        let rows: [HKWorkout] = try await samples(type: HKObjectType.workoutType(), start: start, end: end)
        let calendar = Calendar.autoupdatingCurrent
        return rows.reduce(into: [:]) { result, workout in
            result[calendar.startOfDay(for: workout.startDate), default: 0] += 1
        }
    }

    private func samples<T: HKSample>(type: HKSampleType, start: Date, end: Date) async throws -> [T] {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) {
                _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: (samples as? [T]) ?? [])
            }
            store.execute(query)
        }
    }
}

private struct FitnessDayValues {
    var steps: Double?
    var distance: Double?
    var energy: Double?
    var exercise: Double?
    var heartRateAverage: Double?
    var heartRateMinimum: Double?
    var heartRateMaximum: Double?
    var restingHeartRate: Double?
    var heartRateVariability: Double?
    var bloodPressureSystolic: Double?
    var bloodPressureDiastolic: Double?
    var oxygenSaturationPercent: Double?
    var respiratoryRate: Double?
    var weight: Double?
    var bodyFatPercent: Double?

    mutating func set(key: String, value: Double) {
        switch key {
        case "steps": steps = value
        case "distance": distance = value
        case "energy": energy = value
        case "exercise": exercise = value
        case "heartRateAverage": heartRateAverage = value
        case "heartRateMinimum": heartRateMinimum = value
        case "heartRateMaximum": heartRateMaximum = value
        case "restingHeartRate": restingHeartRate = value
        case "heartRateVariability": heartRateVariability = value
        case "bloodPressureSystolic": bloodPressureSystolic = value
        case "bloodPressureDiastolic": bloodPressureDiastolic = value
        case "oxygenSaturationPercent": oxygenSaturationPercent = value
        case "respiratoryRate": respiratoryRate = value
        case "weight": weight = value
        case "bodyFatPercent": bodyFatPercent = value
        default: break
        }
    }
}

private struct SleepDayValues {
    var totalMinutes = 0.0
    var coreMinutes = 0.0
    var deepMinutes = 0.0
    var remMinutes = 0.0
    var awakeMinutes = 0.0
}

enum FitnessHealthError: LocalizedError {
    case unavailable
    case authorizationDenied

    var errorDescription: String? {
        switch self {
        case .unavailable: return "Apple Health is not available on this device."
        case .authorizationDenied: return "Apple Health access was not granted."
        }
    }
}
