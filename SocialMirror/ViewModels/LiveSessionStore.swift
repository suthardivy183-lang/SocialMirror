import Combine
import Foundation
import UIKit

/// Lifecycle phases for the live recording → analysis → done flow.
enum SessionPhase: Equatable {
    case recording
    case processing
    case done(UUID)
}

/// Owns the audio pipeline + diarization + post-session analyzer for one
/// recording session. Bound to `LiveSessionView` and `ProcessingView`.
@MainActor
final class LiveSessionStore: ObservableObject {
    // Public identity
    let sessionID = UUID()
    let sessionName: String
    let sessionType: SessionType

    // Components (held publicly so views can observe them).
    let pipeline = AudioPipelineCoordinator()
    let clusterer = OnlineSpeakerClusterer()
    let diarizer: DiarizationEngine
    let analyzer: SessionAnalyzer

    // UI state
    @Published var phase: SessionPhase = .recording
    @Published var elapsedSeconds: TimeInterval = 0
    @Published var startError: String?

    private var startDate: Date?
    private var timerTask: Task<Void, Never>?

    init(sessionName: String, sessionType: SessionType) {
        self.sessionName = sessionName
        self.sessionType = sessionType

        let mock = MockSpeakerEmbedder(speakerCount: 3)
        self.diarizer = DiarizationEngine(embedder: mock, clusterer: clusterer)
        self.analyzer = SessionAnalyzer(clusterer: clusterer)

        wirePipeline()
    }

    // MARK: - Wiring

    private func wirePipeline() {
        pipeline.onSegmentReady = { [weak self] segment in
            guard let self else { return }
            Task { _ = await self.diarizer.process(segment) }
        }
    }

    // MARK: - Lifecycle

    func start() async {
        do {
            try await pipeline.start(sessionName: sessionName)
            startDate = Date()
            UIApplication.shared.isIdleTimerDisabled = true
            startTimer()
        } catch {
            startError = (error as? AudioPipelineError) == .permissionDenied
                ? "Microphone permission is required."
                : "Could not start recording: \(error.localizedDescription)"
        }
    }

    func stop() async {
        timerTask?.cancel()
        UIApplication.shared.isIdleTimerDisabled = false

        let raw = await pipeline.stop()
        phase = .processing

        let segments = diarizer.allSegments()
        await analyzer.analyze(
            sessionID: sessionID,
            sessionName: sessionName,
            sessionType: sessionType.rawValue,
            rawData: raw,
            transcript: [], // SFSpeechRecognizer wiring lands in a later part
            diarizedSegments: segments
        )
        phase = .done(sessionID)
    }

    func cancel() async {
        timerTask?.cancel()
        UIApplication.shared.isIdleTimerDisabled = false
        _ = await pipeline.stop()
    }

    // MARK: - Timer

    private func startTimer() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000) // 4 Hz
                if let start = self?.startDate {
                    self?.elapsedSeconds = Date().timeIntervalSince(start)
                }
            }
        }
    }

    // No deinit cleanup of `isIdleTimerDisabled` — `stop()` and `cancel()`
    // always reset it, and the OS clears the flag on app termination.
}
