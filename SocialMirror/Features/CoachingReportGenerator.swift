import Foundation

/// Rules-based coaching report. Picks the single highest-priority issue from
/// the user's features. The user is, by convention, speaker 0 (first speaker
/// detected, which is the device owner who started the session).
nonisolated enum CoachingReportGenerator {
    static func generate(
        for sessionID: UUID,
        userSpeakerID: Int = 0,
        speakers: [SpeakerFeatureSet]
    ) -> CoachingReport {
        guard let user = speakers.first(where: { $0.speakerID == userSpeakerID }) ?? speakers.first else {
            return CoachingReport(
                sessionID: sessionID,
                headline: "No speakers detected",
                insight: "We couldn't extract any speaker activity from this session.",
                actionableTip: "Try recording somewhere quieter, closer to the microphone.",
                speakerFeatures: speakers
            )
        }

        // Priority order matters — highest-impact issue wins.

        if user.talkTimeRatio > 0.70 {
            return CoachingReport(
                sessionID: sessionID,
                headline: "You dominated this conversation",
                insight: "You spoke \(percent(user.talkTimeRatio))% of the time. Research shows conversations feel most balanced at 40–60%.",
                actionableTip: "After your next answer, pause for 2 seconds before continuing.",
                speakerFeatures: speakers
            )
        }

        if user.hedgeWordCount > 15 {
            return CoachingReport(
                sessionID: sessionID,
                headline: "Uncertainty is showing in your language",
                insight: "You used \(user.hedgeWordCount) hedge words. These appear most when describing your own experience.",
                actionableTip: "Replace \"I think I did X\" with \"I did X\".",
                speakerFeatures: speakers
            )
        }

        if user.interruptionCount > 5 {
            return CoachingReport(
                sessionID: sessionID,
                headline: "You're cutting people off",
                insight: "You interrupted \(user.interruptionCount) times. Even when well-intentioned, this signals impatience.",
                actionableTip: "Count to 2 after someone stops speaking before responding.",
                speakerFeatures: speakers
            )
        }

        if user.questionCount < 2 {
            return CoachingReport(
                sessionID: sessionID,
                headline: "You asked almost no questions",
                insight: "You asked only \(user.questionCount) questions. Curiosity is the strongest signal of engagement.",
                actionableTip: "Prepare 3 questions in advance for your next conversation of this type.",
                speakerFeatures: speakers
            )
        }

        if user.avgResponseLatencyMs > 0, user.avgResponseLatencyMs < 200 {
            return CoachingReport(
                sessionID: sessionID,
                headline: "You're responding before people finish",
                insight: "Your average response time was \(Int(user.avgResponseLatencyMs))ms — faster than a typical human reaction time.",
                actionableTip: "Let silence exist for 1 full second before responding.",
                speakerFeatures: speakers
            )
        }

        return CoachingReport(
            sessionID: sessionID,
            headline: "Well-balanced conversation",
            insight: "Your dynamics were in a healthy range.",
            actionableTip: "Notice which topics caused your talk-time to spike.",
            speakerFeatures: speakers
        )
    }

    private static func percent(_ ratio: Double) -> Int {
        Int((ratio * 100).rounded())
    }
}
