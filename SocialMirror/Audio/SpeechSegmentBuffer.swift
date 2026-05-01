import Foundation

/// A bounded chunk of contiguous speech audio between silences.
nonisolated struct SpeechSegment: Identifiable, Sendable {
    let id: UUID
    let samples: [Float]
    let startTime: TimeInterval
    let endTime: TimeInterval
    let durationSeconds: Double

    init(
        id: UUID = UUID(),
        samples: [Float],
        startTime: TimeInterval,
        endTime: TimeInterval,
        durationSeconds: Double
    ) {
        self.id = id
        self.samples = samples
        self.startTime = startTime
        self.endTime = endTime
        self.durationSeconds = durationSeconds
    }
}

/// Accumulates VAD-passing frames into segments. Segments shorter than
/// `minSamples` are silently discarded (too noisy for ECAPA embeddings).
/// Segments are clipped at `maxSamples` to bound memory.
nonisolated final class SpeechSegmentBuffer: @unchecked Sendable {
    static let minSamples: Int = 16_000   // 1.0 s at 16 kHz
    static let maxSamples: Int = 160_000  // 10.0 s at 16 kHz

    private let sampleRate: Double
    private var buffer: [Float] = []
    private var segmentStartTime: TimeInterval = 0
    private var elapsedTime: TimeInterval = 0

    var onSegmentReady: ((SpeechSegment) -> Void)?

    init(sampleRate: Double = AudioCaptureEngine.targetSampleRate) {
        self.sampleRate = sampleRate
        buffer.reserveCapacity(Self.maxSamples)
    }

    /// Feed a frame and its VAD state. Emits a `SpeechSegment` via
    /// `onSegmentReady` when the segment closes (either via `.segmentEnd`
    /// or by hitting `maxSamples`).
    func append(samples: [Float], state: VoiceActivityDetector.VADState) {
        let frameDuration = Double(samples.count) / sampleRate

        switch state {
        case .speech:
            if buffer.isEmpty { segmentStartTime = elapsedTime }
            buffer.append(contentsOf: samples)
            if buffer.count >= Self.maxSamples {
                emit()
            }
        case .silence:
            break
        case .segmentEnd:
            emit()
        }

        elapsedTime += frameDuration
    }

    /// Reset all state. Call between sessions.
    func reset() {
        buffer.removeAll(keepingCapacity: true)
        segmentStartTime = 0
        elapsedTime = 0
    }

    private func emit() {
        defer { buffer.removeAll(keepingCapacity: true) }
        guard buffer.count >= Self.minSamples else { return }
        let dur = Double(buffer.count) / sampleRate
        let segment = SpeechSegment(
            samples: buffer,
            startTime: segmentStartTime,
            endTime: segmentStartTime + dur,
            durationSeconds: dur
        )
        onSegmentReady?(segment)
    }
}
