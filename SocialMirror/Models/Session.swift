import Foundation

struct Session: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var sessionType: String
    var startTime: Date
    var endTime: Date?
    var speakerCount: Int
    var durationSeconds: Double

    init(
        id: UUID = UUID(),
        name: String,
        sessionType: String,
        startTime: Date = Date(),
        endTime: Date? = nil,
        speakerCount: Int = 0,
        durationSeconds: Double = 0
    ) {
        self.id = id
        self.name = name
        self.sessionType = sessionType
        self.startTime = startTime
        self.endTime = endTime
        self.speakerCount = speakerCount
        self.durationSeconds = durationSeconds
    }
}

extension Session {
    /// Caller is responsible for executing on the entity's managed object context queue.
    init(entity: SessionEntity) {
        self.id = entity.id ?? UUID()
        self.name = entity.name ?? ""
        self.sessionType = entity.sessionType ?? ""
        self.startTime = entity.startTime ?? Date()
        self.endTime = entity.endTime
        self.speakerCount = Int(entity.speakerCount)
        self.durationSeconds = entity.durationSeconds
    }
}
