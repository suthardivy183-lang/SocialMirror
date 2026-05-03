import Foundation

/// The single most useful insight surfaced after a session, plus an
/// actionable tip the user can practice next time.
nonisolated struct CoachingReport: Sendable, Identifiable {
    let id: UUID
    let sessionID: UUID
    let headline: String
    let insight: String
    let actionableTip: String
    let speakerFeatures: [SpeakerFeatureSet]
    let generatedAt: Date

    init(
        id: UUID = UUID(),
        sessionID: UUID,
        headline: String,
        insight: String,
        actionableTip: String,
        speakerFeatures: [SpeakerFeatureSet],
        generatedAt: Date = Date()
    ) {
        self.id = id
        self.sessionID = sessionID
        self.headline = headline
        self.insight = insight
        self.actionableTip = actionableTip
        self.speakerFeatures = speakerFeatures
        self.generatedAt = generatedAt
    }
}
