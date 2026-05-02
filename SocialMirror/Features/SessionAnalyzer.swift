import Combine
import CoreData
import Foundation
import os

/// Pipeline state surfaced to the UI while a finished session is being
/// turned into a coaching report.
enum AnalysisStatus: Sendable, Equatable {
    case idle
    case refining     // postSessionRefinement on the clusterer
    case measuring    // SpeakerFeatureAggregator
    case detecting    // DominanceScorer
    case building     // CoachingReportGenerator
    case complete
}

/// Top-level orchestrator. The view layer kicks `analyze(...)` off the
/// moment the user hits "stop", then watches `status` and `report`.
final class SessionAnalyzer: ObservableObject {
    private static let log = Logger(subsystem: "com.divy.SocialMirror", category: "Analyzer")

    @Published var status: AnalysisStatus = .idle
    @Published var report: CoachingReport?

    private let clusterer: OnlineSpeakerClusterer
    private let coreData: CoreDataStack
    private let userSpeakerID: Int

    init(
        clusterer: OnlineSpeakerClusterer,
        coreData: CoreDataStack = .shared,
        userSpeakerID: Int = 0
    ) {
        self.clusterer = clusterer
        self.coreData = coreData
        self.userSpeakerID = userSpeakerID
    }

    func analyze(
        sessionID: UUID = UUID(),
        sessionName: String,
        sessionType: String = "general",
        rawData: AudioPipelineCoordinator.RawSessionData,
        transcript: [TranscriptLine],
        diarizedSegments: [DiarizedSegment]
    ) async {
        // Step 1: refinement
        await update(.refining)
        let mapping = clusterer.postSessionRefinement()
        let refined = diarizedSegments.map { seg -> DiarizedSegment in
            let newID = mapping[seg.speakerID] ?? seg.speakerID
            return DiarizedSegment(
                id: seg.id,
                speechSegment: seg.speechSegment,
                speakerID: newID,
                embedding: seg.embedding
            )
        }
        let refinedTranscript = transcript.map {
            TranscriptLine(
                id: $0.id,
                speakerIndex: mapping[$0.speakerIndex] ?? $0.speakerIndex,
                timestampSeconds: $0.timestampSeconds,
                text: $0.text
            )
        }

        // Step 2: aggregation
        await update(.measuring)
        var features = SpeakerFeatureAggregator.aggregate(
            segments: refined,
            transcript: refinedTranscript
        )

        // Step 3: dominance + confidence per speaker
        await update(.detecting)
        let allFeatures = features
        for (idx, set) in features.enumerated() {
            let scored = DominanceScorer.score(set, relativeTo: allFeatures)
            features[idx].dominanceScore = scored.dominance
            features[idx].confidenceScore = scored.confidence
        }

        // Step 4: report
        await update(.building)
        let generated = CoachingReportGenerator.generate(
            for: sessionID,
            userSpeakerID: userSpeakerID,
            speakers: features
        )

        // Step 5: persist + publish
        await persist(
            sessionID: sessionID,
            sessionName: sessionName,
            sessionType: sessionType,
            rawData: rawData,
            features: features,
            transcript: refinedTranscript
        )

        await update(.complete)
        await MainActor.run { self.report = generated }
        Self.log.info("Analysis complete for session \(sessionID, privacy: .public): \(generated.headline, privacy: .public)")
    }

    // MARK: - Helpers

    private func update(_ next: AnalysisStatus) async {
        await MainActor.run { self.status = next }
    }

    private func persist(
        sessionID: UUID,
        sessionName: String,
        sessionType: String,
        rawData: AudioPipelineCoordinator.RawSessionData,
        features: [SpeakerFeatureSet],
        transcript: [TranscriptLine]
    ) async {
        let ctx = coreData.backgroundContext
        await ctx.perform { [weak self] in
            guard let self else { return }

            let session = SessionEntity(context: ctx)
            session.id = sessionID
            session.name = sessionName
            session.sessionType = sessionType
            session.startTime = rawData.startTime
            session.endTime = rawData.startTime.addingTimeInterval(rawData.totalDuration)
            session.durationSeconds = rawData.totalDuration
            session.speakerCount = Int16(features.count)

            // If audio was saved to disk during stop(), mark this session so the
            // SessionDetailView knows to render the AudioPlayerBarView.
            if AudioStorageManager.shared.exists(sessionID: sessionID) {
                session.audioFileExists = true
                session.audioStoredAt = Date()
                session.audioDurationSeconds = rawData.totalDuration
            }

            for set in features {
                let speaker = SpeakerEntity(context: ctx)
                speaker.id = UUID()
                speaker.speakerIndex = Int16(set.speakerID)
                speaker.talkTimeSeconds = set.totalTalkTime
                speaker.talkTimeRatio = set.talkTimeRatio
                speaker.turnCount = Int16(set.turnCount)
                speaker.interruptionCount = Int16(set.interruptionCount)
                speaker.questionCount = Int16(set.questionCount)
                speaker.hedgeWordCount = Int16(set.hedgeWordCount)
                speaker.avgResponseLatencyMs = set.avgResponseLatencyMs
                speaker.dominanceScore = set.dominanceScore
                speaker.confidenceScore = set.confidenceScore
                speaker.sentimentArcData = encodeFloats(set.sentimentArc)
                speaker.session = session
            }

            for line in transcript {
                let entity = TranscriptLineEntity(context: ctx)
                entity.id = line.id
                entity.speakerIndex = Int16(line.speakerIndex)
                entity.timestampSeconds = line.timestampSeconds
                entity.text = line.text
                entity.session = session
            }

            self.coreData.save(ctx)
        }
    }
}

/// Pack `[Float]` as little-endian bytes for the SpeakerEntity.sentimentArcData blob.
private func encodeFloats(_ values: [Float]) -> Data {
    values.withUnsafeBufferPointer { Data(buffer: $0) }
}
