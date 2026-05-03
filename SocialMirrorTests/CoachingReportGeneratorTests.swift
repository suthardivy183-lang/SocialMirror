import Foundation
import Testing
@testable import SocialMirror

/// Verifies each of the 5 priority-ordered coaching rules fires when its
/// trigger feature is set, and that the balanced fallback fires otherwise.
struct CoachingReportGeneratorTests {
    private static func makeUser(
        id: Int = 0,
        talkRatio: Double = 0.5,
        hedges: Int = 0,
        interruptions: Int = 0,
        questions: Int = 5,
        latencyMs: Float = 800
    ) -> SpeakerFeatureSet {
        var s = SpeakerFeatureSet(speakerID: id)
        s.talkTimeRatio = talkRatio
        s.hedgeWordCount = hedges
        s.interruptionCount = interruptions
        s.questionCount = questions
        s.avgResponseLatencyMs = latencyMs
        return s
    }

    nonisolated static let sharedSessionID = UUID()

    @Test func dominationRuleFires() {
        let user = Self.makeUser(talkRatio: 0.80)
        let report = CoachingReportGenerator.generate(for: Self.sharedSessionID, speakers: [user])
        #expect(report.headline == "You dominated this conversation")
        #expect(report.insight.contains("80%"))
    }

    @Test func hedgeRuleFires() {
        let user = Self.makeUser(talkRatio: 0.5, hedges: 20)
        let report = CoachingReportGenerator.generate(for: Self.sharedSessionID, speakers: [user])
        #expect(report.headline == "Uncertainty is showing in your language")
        #expect(report.insight.contains("20"))
    }

    @Test func interruptionRuleFires() {
        let user = Self.makeUser(talkRatio: 0.5, interruptions: 8)
        let report = CoachingReportGenerator.generate(for: Self.sharedSessionID, speakers: [user])
        #expect(report.headline == "You're cutting people off")
        #expect(report.insight.contains("8"))
    }

    @Test func lowQuestionsRuleFires() {
        let user = Self.makeUser(talkRatio: 0.5, questions: 0)
        let report = CoachingReportGenerator.generate(for: Self.sharedSessionID, speakers: [user])
        #expect(report.headline == "You asked almost no questions")
    }

    @Test func fastResponseRuleFires() {
        let user = Self.makeUser(talkRatio: 0.5, latencyMs: 120)
        let report = CoachingReportGenerator.generate(for: Self.sharedSessionID, speakers: [user])
        #expect(report.headline == "You're responding before people finish")
        #expect(report.insight.contains("120"))
    }

    @Test func balancedFallbackFires() {
        // No threshold triggered.
        let user = Self.makeUser()
        let report = CoachingReportGenerator.generate(for: Self.sharedSessionID, speakers: [user])
        #expect(report.headline == "Well-balanced conversation")
    }

    @Test func priorityOrderTalkRatioBeatsHedges() {
        // Both triggers active — talk-time-domination wins because it's first.
        let user = Self.makeUser(talkRatio: 0.85, hedges: 30)
        let report = CoachingReportGenerator.generate(for: Self.sharedSessionID, speakers: [user])
        #expect(report.headline == "You dominated this conversation")
    }

    @Test func emptySpeakersGivesGracefulMessage() {
        let report = CoachingReportGenerator.generate(for: Self.sharedSessionID, speakers: [])
        #expect(report.headline == "No speakers detected")
    }
}
