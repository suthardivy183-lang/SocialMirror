import Foundation
import Testing
@testable import SocialMirror

/// Runs a real MP3 through the full import pipeline so we can eyeball results.
/// Prints intermediate counts via `print()` so the test log captures them.
struct RealAudioImportTest {
    private static let path = "/Users/suthardivydevendrabhai/Downloads/The_Onboarding_Desk.mp3"
    private static let outputPath = "/tmp/sm_onboarding_results.txt"

    /// Append a line to the well-known output file (test stdout is captured
    /// into the .xcresult bundle, so this is the cleanest way to surface
    /// pipeline numbers back to the operator).
    static func write(_ line: String) {
        let content = line + "\n"
        if let data = content.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: outputPath) {
                if let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: outputPath)) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    try? handle.close()
                }
            } else {
                try? data.write(to: URL(fileURLWithPath: outputPath))
            }
        }
    }

    @MainActor
    @Test func processOnboardingDesk() async throws {
        // Wipe previous run.
        try? FileManager.default.removeItem(atPath: Self.outputPath)

        let url = URL(fileURLWithPath: Self.path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            Self.write("[skip] file not found at \(url.path)")
            return
        }

        // 1) Load + resample.
        let importer = await AudioImporter()
        let (samples, duration, _) = try await importer.loadAudioFile(url: url)
        Self.write("=== LOAD ===")
        Self.write("  samples: \(samples.count) (16 kHz mono Float32)")
        Self.write("  duration: \(String(format: "%.2f", duration))s")
        Self.write("  sample-rate-after-resample: \(Double(samples.count) / duration) Hz")

        // 2) VAD + segmentation.
        // Test override: 2 s segments — sweet spot per ECAPA literature.
        var vad = VoiceActivityDetector()
        let buffer = SpeechSegmentBuffer(
            minSamples: 8_000,    // 0.5 s
            maxSamples: 32_000    // 2.0 s
        )
        var segments: [SpeechSegment] = []
        buffer.onSegmentReady = { segments.append($0) }

        let frameSize = AudioCaptureEngine.frameSize
        var offset = 0
        var speechFrames = 0
        var silenceFrames = 0
        while offset + frameSize <= samples.count {
            let frame = Array(samples[offset ..< offset + frameSize])
            let state = vad.processingFrame(frame)
            switch state {
            case .speech: speechFrames += 1
            case .silence: silenceFrames += 1
            case .segmentEnd: speechFrames += 1 // counted as one of each
            }
            buffer.append(samples: frame, state: state)
            offset += frameSize
        }
        Self.write("=== VAD ===")
        Self.write("  total frames (20 ms): \(samples.count / frameSize)")
        Self.write("  speech frames: \(speechFrames)  (\(Int(Double(speechFrames) / Double(speechFrames + silenceFrames) * 100))%)")
        Self.write("  silence frames: \(silenceFrames)")
        Self.write("  segments emitted: \(segments.count)")
        for (i, seg) in segments.enumerated() {
            Self.write(String(format: "    seg %d: %.2fs at %.2fs", i, seg.durationSeconds, seg.startTime))
        }

        // 3) Diarization (real ECAPA via Core ML, looser threshold).
        let clusterer = OnlineSpeakerClusterer(similarityThreshold: 0.65)
        let embedder: any SpeakerEmbeddingProvider
        do {
            embedder = try CoreMLSpeakerEmbedder()
        } catch {
            Self.write("[skip] ECAPA model not available: \(error.localizedDescription)")
            return
        }
        let diarizer = await DiarizationEngine(embedder: embedder, clusterer: clusterer)
        var diarized: [DiarizedSegment] = []
        for seg in segments {
            diarized.append(await diarizer.process(seg))
        }
        let onlineGrouped = Dictionary(grouping: diarized, by: { $0.speakerID })
        Self.write("=== DIARIZATION (online) ===")
        Self.write("  detected speakers: \(onlineGrouped.keys.count)")
        for (id, segs) in onlineGrouped.sorted(by: { $0.key < $1.key }) {
            let total = segs.reduce(0.0) { $0 + $1.speechSegment.durationSeconds }
            Self.write(String(format: "    speaker %d: %d segments, %.2fs talk time", id, segs.count, total))
        }

        // 3b) Post-session agglomerative refinement.
        let mapping = clusterer.postSessionRefinement()
        let refined = diarized.map { d -> DiarizedSegment in
            DiarizedSegment(
                id: d.id,
                speechSegment: d.speechSegment,
                speakerID: mapping[d.speakerID] ?? d.speakerID,
                embedding: d.embedding
            )
        }
        let refinedGrouped = Dictionary(grouping: refined, by: { $0.speakerID })
        Self.write("=== DIARIZATION (after postSessionRefinement) ===")
        Self.write("  detected speakers: \(refinedGrouped.keys.count)")
        Self.write("  mapping (online → refined): \(mapping.sorted(by: { $0.key < $1.key }).map { "\($0.key)→\($0.value)" }.joined(separator: ", "))")
        for (id, segs) in refinedGrouped.sorted(by: { $0.key < $1.key }) {
            let total = segs.reduce(0.0) { $0 + $1.speechSegment.durationSeconds }
            Self.write(String(format: "    speaker %d: %d segments, %.2fs talk time", id, segs.count, total))
        }

        // 4) Feature aggregation (using refined IDs).
        let features = SpeakerFeatureAggregator.aggregate(segments: refined, transcript: [])
        Self.write("=== FEATURES ===")
        for f in features {
            Self.write(String(
                format: "    speaker %d: talk=%.0f%%, turns=%d, pitch≈%.0f Hz, energy=%.1f dB",
                f.speakerID,
                f.talkTimeRatio * 100,
                f.turnCount,
                Double(f.avgPitch),
                Double(f.avgEnergyDB)
            ))
        }

        // 5) Dominance + confidence (rules-based scoring).
        var scored = features
        for (idx, set) in scored.enumerated() {
            let s = DominanceScorer.score(set, relativeTo: scored)
            scored[idx].dominanceScore = s.dominance
            scored[idx].confidenceScore = s.confidence
        }
        Self.write("=== SCORES ===")
        for f in scored {
            Self.write(String(
                format: "    speaker %d: dominance=%.2f, confidence=%.2f",
                f.speakerID, Double(f.dominanceScore), Double(f.confidenceScore)
            ))
        }

        // 6) Coaching report.
        let report = CoachingReportGenerator.generate(
            for: UUID(),
            userSpeakerID: 0,
            speakers: scored
        )
        Self.write("=== REPORT ===")
        Self.write("  headline: \(report.headline)")
        Self.write("  insight:  \(report.insight)")
        Self.write("  tip:      \(report.actionableTip)")

        // Sanity assertions so the test passes.
        #expect(samples.count > 0)
        #expect(duration > 25 && duration < 35)
    }
}
