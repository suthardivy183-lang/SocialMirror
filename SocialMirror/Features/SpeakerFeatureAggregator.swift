import Foundation

/// Per-speaker rollup of every numeric feature the coaching report needs.
struct SpeakerFeatureSet: Identifiable, Sendable {
    let speakerID: Int

    var totalTalkTime: TimeInterval = 0
    var talkTimeRatio: Double = 0       // filled after all speakers known
    var turnCount: Int = 0
    var interruptionCount: Int = 0
    var questionCount: Int = 0
    var hedgeWordCount: Int = 0

    var avgPitch: Float = 0
    var pitchVariance: Float = 0
    var avgEnergyDB: Float = -90
    var avgSpeechRate: Float = 0

    var avgResponseLatencyMs: Float = 0
    var responseLatencies: [Float] = []

    var dominanceScore: Float = 0       // filled by DominanceScorer
    var confidenceScore: Float = 0      // filled by DominanceScorer
    var sentimentArc: [Float] = []      // 10-second rolling windows

    var id: Int { speakerID }
}

/// Walks a session's diarized segments + transcript and emits one
/// `SpeakerFeatureSet` per detected speaker.
nonisolated enum SpeakerFeatureAggregator {
    /// Two segments overlap if the second starts before the first ends, by
    /// more than this amount. Anything shorter is just a normal turn handoff.
    static let interruptionOverlapThreshold: TimeInterval = 0.2

    /// 10-second windows for the sentiment-arc placeholder (energy proxy).
    static let sentimentWindowSeconds: TimeInterval = 10

    static func aggregate(
        segments: [DiarizedSegment],
        transcript: [TranscriptLine]
    ) -> [SpeakerFeatureSet] {
        guard !segments.isEmpty else { return [] }

        let segmentsSorted = segments.sorted { $0.speechSegment.startTime < $1.speechSegment.startTime }

        // Bucket per speaker.
        var sets: [Int: SpeakerFeatureSet] = [:]
        var pitchTracks: [Int: [Float]] = [:]
        var energies: [Int: [Float]] = [:]

        // Group transcript by speaker for hedge/question counts and word totals.
        var speakerText: [Int: [String]] = [:]
        for line in transcript {
            speakerText[Int(line.speakerIndex), default: []].append(line.text)
        }

        let hedgeDetector = HedgeWordDetector()

        // ----- per-segment pass -----
        var lastEndTime: TimeInterval = 0
        var lastSpeakerID: Int? = nil

        for diarized in segmentsSorted {
            let id = diarized.speakerID
            var set = sets[id] ?? SpeakerFeatureSet(speakerID: id)
            let seg = diarized.speechSegment

            set.totalTalkTime += seg.durationSeconds
            set.turnCount += 1

            // Interruption: this segment starts > 0.2s before the previous one ended.
            if let prevSpeaker = lastSpeakerID,
               prevSpeaker != id,
               (lastEndTime - seg.startTime) > interruptionOverlapThreshold {
                set.interruptionCount += 1
            }

            // Response latency: gap from previous (different) speaker's end to this start.
            if let prevSpeaker = lastSpeakerID,
               prevSpeaker != id,
               seg.startTime > lastEndTime {
                let latencyMs = Float((seg.startTime - lastEndTime) * 1000)
                set.responseLatencies.append(latencyMs)
            }

            // Acoustic features.
            let pitch = AcousticFeatureExtractor.extractPitch(from: seg.samples)
            pitchTracks[id, default: []].append(pitch)
            energies[id, default: []].append(AcousticFeatureExtractor.extractEnergy(from: seg.samples))

            sets[id] = set
            lastEndTime = max(lastEndTime, seg.endTime)
            lastSpeakerID = id
        }

        // ----- post-pass derivations -----
        let totalTalkTime = sets.values.reduce(0) { $0 + $1.totalTalkTime }

        for (id, var set) in sets {
            // Talk-time ratio.
            set.talkTimeRatio = totalTalkTime > 0 ? set.totalTalkTime / totalTalkTime : 0

            // Acoustic averages.
            let pitches = pitchTracks[id, default: []]
            let voiced = pitches.filter { $0 > 0 }
            set.avgPitch = voiced.isEmpty ? 0 : voiced.reduce(0, +) / Float(voiced.count)
            set.pitchVariance = AcousticFeatureExtractor.extractPitchVariance(pitches: pitches)

            let energyVals = energies[id, default: []]
            set.avgEnergyDB = energyVals.isEmpty ? -90 : energyVals.reduce(0, +) / Float(energyVals.count)

            // Response latency.
            if !set.responseLatencies.isEmpty {
                set.avgResponseLatencyMs = set.responseLatencies.reduce(0, +) / Float(set.responseLatencies.count)
            }

            // Transcript-derived counts (use whatever lines map to this speaker).
            let texts = speakerText[id] ?? []
            let joined = texts.joined(separator: " ")
            set.hedgeWordCount = hedgeDetector.count(in: joined)
            set.questionCount = texts.filter { $0.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("?") }.count

            let wordCount = joined.split { !$0.isLetter && !$0.isNumber }.count
            set.avgSpeechRate = AcousticFeatureExtractor.extractSpeechRate(
                wordCount: wordCount,
                duration: set.totalTalkTime
            )

            // Sentiment-arc placeholder: per-window mean energy normalized to 0–1.
            set.sentimentArc = sentimentArc(energies: energies, speakerID: id, totalDuration: lastEndTime)

            sets[id] = set
        }

        return sets.values.sorted { $0.speakerID < $1.speakerID }
    }

    /// V1 sentiment proxy: per-10-second-window normalized energy. Real
    /// sentiment will replace this once the NL model lands.
    private static func sentimentArc(
        energies: [Int: [Float]],
        speakerID id: Int,
        totalDuration: TimeInterval
    ) -> [Float] {
        guard totalDuration > 0 else { return [] }
        let windows = max(1, Int(ceil(totalDuration / sentimentWindowSeconds)))
        let values = energies[id] ?? []
        guard !values.isEmpty else { return Array(repeating: 0, count: windows) }
        // Coarse mapping: distribute the per-segment energies evenly across windows.
        let chunk = max(1, values.count / windows)
        var arc: [Float] = []
        var i = 0
        while i < values.count, arc.count < windows {
            let slice = Array(values[i ..< min(i + chunk, values.count)])
            arc.append(slice.reduce(0, +) / Float(slice.count))
            i += chunk
        }
        // Normalize -90...0 dB → 0...1
        return arc.map { Float(min(1, max(0, ($0 + 90) / 90))) }
    }
}
