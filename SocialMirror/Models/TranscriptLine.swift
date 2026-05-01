import Foundation

struct TranscriptLine: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var speakerIndex: Int
    var timestampSeconds: Double
    var text: String

    init(
        id: UUID = UUID(),
        speakerIndex: Int,
        timestampSeconds: Double,
        text: String
    ) {
        self.id = id
        self.speakerIndex = speakerIndex
        self.timestampSeconds = timestampSeconds
        self.text = text
    }
}

extension TranscriptLine {
    /// Caller is responsible for executing on the entity's managed object context queue.
    init(entity: TranscriptLineEntity) {
        self.id = entity.id ?? UUID()
        self.speakerIndex = Int(entity.speakerIndex)
        self.timestampSeconds = entity.timestampSeconds
        self.text = entity.text ?? ""
    }
}
