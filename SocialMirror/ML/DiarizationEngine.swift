import Combine
import Foundation
import os

/// Diarized audio segment: the original speech segment plus the speaker
/// assignment and the embedding vector that produced it.
struct DiarizedSegment: Identifiable, Sendable {
    let id: UUID
    let speechSegment: SpeechSegment
    let speakerID: Int
    let embedding: SpeakerEmbedding

    init(
        id: UUID = UUID(),
        speechSegment: SpeechSegment,
        speakerID: Int,
        embedding: SpeakerEmbedding
    ) {
        self.id = id
        self.speechSegment = speechSegment
        self.speakerID = speakerID
        self.embedding = embedding
    }
}

/// Connects an embedder to the online clusterer and tracks per-speaker
/// statistics. Views observe published state for live UI updates.
final class DiarizationEngine: ObservableObject {
    private static let log = Logger(subsystem: "com.divy.SocialMirror", category: "Diarization")

    // MARK: - Published state
    @Published var detectedSpeakerCount: Int = 0
    @Published var speakerTalkTimes: [Int: TimeInterval] = [:]

    // MARK: - Components
    private let embedder: any SpeakerEmbeddingProvider
    private let clusterer: OnlineSpeakerClusterer
    private let segments = OSAllocatedUnfairLock(initialState: [DiarizedSegment]())

    nonisolated(unsafe) var onSegmentDiarized: ((DiarizedSegment) -> Void)?

    init(
        embedder: any SpeakerEmbeddingProvider,
        clusterer: OnlineSpeakerClusterer = OnlineSpeakerClusterer()
    ) {
        self.embedder = embedder
        self.clusterer = clusterer
    }

    /// Production initializer — always uses `CoreMLSpeakerEmbedder` backed by
    /// `ECAPA.mlpackage`. Throws if the model isn't in the bundle. Tests should
    /// use the explicit `init(embedder:clusterer:)` overload to inject a mock.
    convenience init(clusterer: OnlineSpeakerClusterer = OnlineSpeakerClusterer()) throws {
        let embedder = try CoreMLSpeakerEmbedder()
        self.init(embedder: embedder, clusterer: clusterer)
    }

    // MARK: - Public API

    func process(_ segment: SpeechSegment) async -> DiarizedSegment {
        let embedding: SpeakerEmbedding
        do {
            embedding = try await embedder.embed(segment)
        } catch {
            Self.log.error("Embedding failed: \(error.localizedDescription, privacy: .public)")
            embedding = []
        }

        let speakerID = clusterer.assign(
            embedding: embedding,
            at: segment.startTime,
            duration: segment.durationSeconds
        )

        let diarized = DiarizedSegment(
            speechSegment: segment,
            speakerID: speakerID,
            embedding: embedding
        )
        segments.withLock { $0.append(diarized) }
        onSegmentDiarized?(diarized)

        let speakerCount = clusterer.clusters.count
        let talkTimes = Dictionary(uniqueKeysWithValues: clusterer.clusters.map { ($0.speakerID, $0.totalTalkTime) })
        await MainActor.run {
            self.detectedSpeakerCount = speakerCount
            self.speakerTalkTimes = talkTimes
        }
        return diarized
    }

    func allSegments() -> [DiarizedSegment] {
        segments.withLock { $0 }
    }

    func reset() {
        clusterer.reset()
        segments.withLock { $0.removeAll(keepingCapacity: true) }
        Task { @MainActor in
            self.detectedSpeakerCount = 0
            self.speakerTalkTimes = [:]
        }
    }
}
