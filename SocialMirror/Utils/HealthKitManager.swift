import Foundation
import HealthKit
import os

/// Optional HealthKit integration. The HealthKit *capability* must be enabled
/// on the SocialMirror target for `HKHealthStore.isHealthDataAvailable()` to
/// return `true`; without it, every method here returns `nil` gracefully.
nonisolated final class HealthKitManager: @unchecked Sendable {
    static let shared = HealthKitManager()
    private static let log = Logger(subsystem: "com.divy.SocialMirror", category: "HealthKit")

    private let store = HKHealthStore()

    private init() {}

    // MARK: - Permission

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }

        var types: Set<HKObjectType> = []
        if let hrv = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) { types.insert(hrv) }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { types.insert(sleep) }
        if let steps = HKObjectType.quantityType(forIdentifier: .stepCount) { types.insert(steps) }

        do {
            try await store.requestAuthorization(toShare: [], read: types)
            return true
        } catch {
            Self.log.warning("HealthKit auth failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    // MARK: - Snapshot

    /// Snapshot of HRV (last sample today), sleep hours (previous night), and
    /// step count (today). Returns `nil` if HealthKit is unavailable or no data exists.
    func contextAt(_ date: Date) async -> BiometricContext? {
        guard isAvailable else { return nil }
        async let sleep = lastNightSleepHours(referenceDate: date)
        async let hrv = morningHRV(referenceDate: date)
        async let steps = todaySteps(referenceDate: date)
        let ctx = await BiometricContext(
            lastNightSleepHours: sleep,
            morningHRV: hrv,
            stepCount: steps
        )
        // If everything's nil, the context is meaningless.
        if ctx.lastNightSleepHours == nil, ctx.morningHRV == nil, ctx.stepCount == nil { return nil }
        return ctx
    }

    // MARK: - Per-metric queries

    private func lastNightSleepHours(referenceDate: Date) async -> Double? {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        let cal = Calendar.current
        let endOfYesterday = cal.startOfDay(for: referenceDate)
        guard let startOfYesterday = cal.date(byAdding: .day, value: -1, to: endOfYesterday) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: startOfYesterday, end: endOfYesterday)

        return await withCheckedContinuation { cont in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                guard let samples = samples as? [HKCategorySample] else {
                    cont.resume(returning: nil); return
                }
                let asleep = samples.filter { sample in
                    if #available(iOS 16.0, *) {
                        return sample.value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
                            || sample.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue
                            || sample.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue
                            || sample.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue
                    } else {
                        return sample.value == HKCategoryValueSleepAnalysis.asleep.rawValue
                    }
                }
                let totalSeconds = asleep.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                cont.resume(returning: totalSeconds > 0 ? totalSeconds / 3600 : nil)
            }
            store.execute(query)
        }
    }

    private func morningHRV(referenceDate: Date) async -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return nil }
        let cal = Calendar.current
        let start = cal.startOfDay(for: referenceDate)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: referenceDate)
        let unit = HKUnit.secondUnit(with: .milli)

        return await withCheckedContinuation { cont in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                guard let sample = (samples as? [HKQuantitySample])?.first else {
                    cont.resume(returning: nil); return
                }
                cont.resume(returning: sample.quantity.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    private func todaySteps(referenceDate: Date) async -> Int? {
        guard let type = HKObjectType.quantityType(forIdentifier: .stepCount) else { return nil }
        let cal = Calendar.current
        let start = cal.startOfDay(for: referenceDate)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: referenceDate)

        return await withCheckedContinuation { cont in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
                guard let total = stats?.sumQuantity()?.doubleValue(for: .count()), total > 0 else {
                    cont.resume(returning: nil); return
                }
                cont.resume(returning: Int(total))
            }
            store.execute(query)
        }
    }
}
