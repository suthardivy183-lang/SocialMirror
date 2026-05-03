import Combine
import Foundation
import Speech
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

    /// Set if the ECAPA model couldn't be loaded at construction time.
    /// `start()` surfaces it as `startError` before recording begins.
    private var embedderInitError: String?

    private var startDate: Date?
    private var timerTask: Task<Void, Never>?

    init(sessionName: String, sessionType: SessionType) {
        self.sessionName = sessionName
        self.sessionType = sessionType

        // Production: always use ECAPA. If the bundle is missing the model
        // for any reason, fall back to a no-op mock so the rest of the app
        // doesn't crash, and `start()` will surface the error to the user.
        do {
            let embedder = try CoreMLSpeakerEmbedder()
            self.diarizer = DiarizationEngine(embedder: embedder, clusterer: clusterer)
        } catch {
            self.embedderInitError = "Speaker embedding model unavailable: \(error.localizedDescription)"
            self.diarizer = DiarizationEngine(embedder: MockSpeakerEmbedder(speakerCount: 1), clusterer: clusterer)
        }
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
        if let error = embedderInitError {
            startError = error
            Haptics.notify(.error)
            return
        }
        do {
            try await pipeline.start(sessionName: sessionName)
            startDate = Date()
            UIApplication.shared.isIdleTimerDisabled = true
            Haptics.notify(.success)
            // Kick off speech-recognition authorization in the background — it may
            // already be granted, but if not, the prompt happens before the user
            // taps Stop so transcription is ready when it's needed.
            Task { _ = await TranscriptionEngine.requestAuthorization() }
            startTimer()
        } catch {
            startError = (error as? AudioPipelineError) == .permissionDenied
                ? "Microphone permission is required."
                : "Could not start recording: \(error.localizedDescription)"
            Haptics.notify(.error)
        }
    }

    func stop() async {
        timerTask?.cancel()
        UIApplication.shared.isIdleTimerDisabled = false
        Haptics.notify(.warning)

        let raw = await pipeline.stop()
        phase = .processing

        let segments = diarizer.allSegments()

        // Save audio to disk if the user opted in. This lets the player UI in
        // SessionDetailView appear; the analyzer reads `AudioStorageManager.exists`
        // to set the `audioFileExists` flag on the persisted session.
        if AudioStorageManager.shared.saveAudioEnabled {
            let allSamples = segments.flatMap { $0.speechSegment.samples }
            if !allSamples.isEmpty {
                _ = try? await AudioStorageManager.shared.save(
                    samples: allSamples,
                    sessionID: sessionID
                )
            }
        }

        // Transcribe segments concurrently (no-op when on-device recognition
        // is unavailable or speech permission was denied).
        let transcript = await TranscriptionEngine().transcribeAll(segments)

        await analyzer.analyze(
            sessionID: sessionID,
            sessionName: sessionName,
            sessionType: sessionType.rawValue,
            rawData: raw,
            transcript: transcript,
            diarizedSegments: segments
        )

        // Release the in-memory audio now that it's been persisted (or discarded).
        diarizer.reset()
        pipeline.cleanupAudioMemory()

        Haptics.notify(.success)
        phase = .done(sessionID)
    }

    func cancel() async {
        timerTask?.cancel()
        UIApplication.shared.isIdleTimerDisabled = false
        _ = await pipeline.stop()
        diarizer.reset()
        pipeline.cleanupAudioMemory()
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
