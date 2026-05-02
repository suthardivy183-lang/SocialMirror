import Foundation

/// Rules-based scoring for "dominance" and "confidence". Both come out of
/// the same `SpeakerFeatureSet`, normalized against the rest of the speakers
/// in the session so the numbers are session-relative rather than absolute.
nonisolated enum DominanceScorer {
    static func score(
        _ features: SpeakerFeatureSet,
        relativeTo allFeatures: [SpeakerFeatureSet]
    ) -> (dominance: Float, confidence: Float) {
        // ---- session-relative reference values ----
        let maxInterruptions = max(1, allFeatures.map(\.interruptionCount).max() ?? 1)
        let maxHedges = max(1, allFeatures.map(\.hedgeWordCount).max() ?? 1)
        let maxEnergy = (allFeatures.map(\.avgEnergyDB).max() ?? 0)
        let minEnergy = (allFeatures.map(\.avgEnergyDB).min() ?? -90)
        let maxPitchVar = max(0.001, allFeatures.map(\.pitchVariance).max() ?? 0.001)
        let allLatencies = allFeatures.flatMap(\.responseLatencies)
        let maxLatency = max(200, allLatencies.max() ?? 200) // anchor at >=200 ms

        // ---- normalized component metrics (each in 0...1) ----
        let talkTimeRatio = Float(features.talkTimeRatio).clamped(0, 1)

        let interruptionRate = Float(features.interruptionCount) / Float(maxInterruptions)
        let hedgeRate = Float(features.hedgeWordCount) / Float(maxHedges)

        let energySpread = max(0.001, maxEnergy - minEnergy)
        let energyNormalized = ((features.avgEnergyDB - minEnergy) / energySpread).clamped(0, 1)

        // High variance ⇒ unstable pitch ⇒ low stability.
        let pitchStability: Float = (1 - (features.pitchVariance / maxPitchVar)).clamped(0, 1)

        // Faster than 200 ms = full speed; ≥maxLatency = 0.
        let responseSpeed: Float = features.avgResponseLatencyMs == 0
            ? 0.5 // no measured response — neutral
            : (1 - (features.avgResponseLatencyMs / maxLatency)).clamped(0, 1)

        // ---- weighted blends ----
        let dominance = (
            talkTimeRatio * 0.35
                + interruptionRate * 0.25
                + (1 - hedgeRate) * 0.20
                + energyNormalized * 0.20
        ).clamped(0, 1)

        let confidence = (
            (1 - hedgeRate) * 0.40
                + pitchStability * 0.30
                + responseSpeed * 0.30
        ).clamped(0, 1)

        return (dominance, confidence)
    }
}

private extension Float {
    nonisolated func clamped(_ lo: Float, _ hi: Float) -> Float { min(max(self, lo), hi) }
}
