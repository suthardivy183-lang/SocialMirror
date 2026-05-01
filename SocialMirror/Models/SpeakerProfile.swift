import Foundation

struct SpeakerProfile: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var speakerIndex: Int
    var assignedName: String?
    var talkTimeSeconds: Double
    var talkTimeRatio: Double
    var turnCount: Int
    var interruptionCount: Int
    var questionCount: Int
    var hedgeWordCount: Int
    var avgResponseLatencyMs: Float
    var dominanceScore: Float
    var confidenceScore: Float
    var sentimentArcData: Data?

    init(
        id: UUID = UUID(),
        speakerIndex: Int,
        assignedName: String? = nil,
        talkTimeSeconds: Double = 0,
        talkTimeRatio: Double = 0,
        turnCount: Int = 0,
        interruptionCount: Int = 0,
        questionCount: Int = 0,
        hedgeWordCount: Int = 0,
        avgResponseLatencyMs: Float = 0,
        dominanceScore: Float = 0,
        confidenceScore: Float = 0,
        sentimentArcData: Data? = nil
    ) {
        self.id = id
        self.speakerIndex = speakerIndex
        self.assignedName = assignedName
        self.talkTimeSeconds = talkTimeSeconds
        self.talkTimeRatio = talkTimeRatio
        self.turnCount = turnCount
        self.interruptionCount = interruptionCount
        self.questionCount = questionCount
        self.hedgeWordCount = hedgeWordCount
        self.avgResponseLatencyMs = avgResponseLatencyMs
        self.dominanceScore = dominanceScore
        self.confidenceScore = confidenceScore
        self.sentimentArcData = sentimentArcData
    }
}

extension SpeakerProfile {
    /// Caller is responsible for executing on the entity's managed object context queue.
    init(entity: SpeakerEntity) {
        self.id = entity.id ?? UUID()
        self.speakerIndex = Int(entity.speakerIndex)
        self.assignedName = entity.assignedName
        self.talkTimeSeconds = entity.talkTimeSeconds
        self.talkTimeRatio = entity.talkTimeRatio
        self.turnCount = Int(entity.turnCount)
        self.interruptionCount = Int(entity.interruptionCount)
        self.questionCount = Int(entity.questionCount)
        self.hedgeWordCount = Int(entity.hedgeWordCount)
        self.avgResponseLatencyMs = entity.avgResponseLatencyMs
        self.dominanceScore = entity.dominanceScore
        self.confidenceScore = entity.confidenceScore
        self.sentimentArcData = entity.sentimentArcData
    }
}
