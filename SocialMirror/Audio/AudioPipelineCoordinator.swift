import Combine
import Foundation
import os

/// Top-level controller that wires the audio session, capture engine, VAD,
/// and segment buffer together. Views observe this object directly.
final class AudioPipelineCoordinator: ObservableObject {
    private static let log = Logger(subsystem: "com.divy.SocialMirror", category: "Pipeline")

    // MARK: - Published state
    @Published var isRunning: Bool = false
    @Published var currentLevel: Float = 0
    @Published var detectedSpeakerCount: Int = 0

    // MARK: - Components
    private let session: AudioSessionManager
    private let engine: AudioCaptureEngine
    private var vad: VoiceActivityDetector
    private let segmentBuffer: SpeechSegmentBuffer

    // MARK: - Per-session state
    /// Async-safe lock around the segment list (audio thread appends; main thread reads on stop).
    private let segments = OSAllocatedUnfairLock(initialState: [SpeechSegment]())
    private var sessionName: String = ""
    private var startDate: Date = Date()

    /// External hook called whenever the buffer emits a closed segment.
    /// View models subscribe to push segments through the diarizer in real time.
    nonisolated(unsafe) var onSegmentReady: ((SpeechSegment) -> Void)?

    init(
        session: AudioSessionManager = AudioSessionManager(),
        engine: AudioCaptureEngine = AudioCaptureEngine(),
        vad: VoiceActivityDetector = VoiceActivityDetector(),
        segmentBuffer: SpeechSegmentBuffer = SpeechSegmentBuffer()
    ) {
        self.session = session
        self.engine = engine
        self.vad = vad
        self.segmentBuffer = segmentBuffer

        wireCallbacks()
    }

    // MARK: - Public API

    struct RawSessionData: Sendable {
        let segments: [SpeechSegment]
        let totalDuration: TimeInterval
        let startTime: Date
    }

    func start(sessionName: String) async throws {
        self.sessionName = sessionName

        let granted = await session.requestPermission()
        guard granted else { throw AudioPipelineError.permissionDenied }

        try session.activate()
        try engine.start()

        segments.withLock { $0.removeAll(keepingCapacity: true) }
        vad.reset()
        segmentBuffer.reset()

        startDate = Date()
        await MainActor.run { self.isRunning = true }
        Self.log.info("Pipeline started for session: \(sessionName, privacy: .public)")
    }

    func stop() async -> RawSessionData {
        engine.stop()
        try? session.deactivate()

        await MainActor.run {
            self.isRunning = false
            self.currentLevel = 0
        }

        let total = Date().timeIntervalSince(startDate)
        let snapshot = segments.withLock { $0 }

        Self.log.info("Pipeline stopped — \(snapshot.count, privacy: .public) segments, \(total, privacy: .public)s")
        return RawSessionData(segments: snapshot, totalDuration: total, startTime: startDate)
    }

    /// Drop all in-memory audio. Call after the analyzer has persisted the
    /// session — the raw `[Float]` arrays inside `SpeechSegment` can be
    /// hundreds of MB for long sessions and should be released ASAP.
    func cleanupAudioMemory() {
        segments.withLock { $0.removeAll(keepingCapacity: false) }
    }

    // MARK: - Private

    private func wireCallbacks() {
        engine.onAudioFrame = { [weak self] frame in
            self?.process(frame: frame)
        }
        segmentBuffer.onSegmentReady = { [weak self] segment in
            self?.segments.withLock { $0.append(segment) }
            self?.onSegmentReady?(segment)
        }
        session.onInterruptionBegan = { [weak self] in
            self?.engine.stop()
        }
        session.onRouteChanged = { [weak self] _ in
            // Route change can invalidate the engine; safest is to stop.
            self?.engine.stop()
        }
    }

    /// Audio-thread entry point.
    private func process(frame: [Float]) {
        let state = vad.processingFrame(frame)
        segmentBuffer.append(samples: frame, state: state)
    }
}

// MARK: - Errors
enum AudioPipelineError: Error {
    case permissionDenied
}
