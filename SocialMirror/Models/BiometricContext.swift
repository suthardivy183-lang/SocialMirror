import Foundation

/// Snapshot of HealthKit data captured at session-start time and (optionally)
/// attached to the session for correlation with conversation dynamics.
struct BiometricContext: Sendable, Codable {
    var lastNightSleepHours: Double?
    var morningHRV: Double?
    var stepCount: Int?
}
