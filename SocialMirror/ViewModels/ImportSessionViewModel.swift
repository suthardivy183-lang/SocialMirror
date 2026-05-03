import Combine
import Foundation

/// Drives the Files-app / Voice-Memos import flow: load + resample audio,
/// run the same VAD → diarize → transcribe → analyze chain as the live
/// pipeline, optionally save the original audio, and surface a
/// `completedSession` for navigation.
@MainActor
final class ImportSessionViewModel: ObservableObject {
    @Published var isProcessing = false
    @Published var processingStep = ""
    @Published var progress: Double = 0
    @Published var completedSession: Session?
    @Published var error: String?

    private let importer = AudioImporter()
    private let transcriber = TranscriptionEngine()

    init() {}

    /// Maximum file length we accept (3 hours). Anything longer is rejected
    /// before we spend memory on it.
    static let maxDurationSeconds: TimeInterval = 3 * 60 * 60

    func process(url: URL, sessionName: String, sessionType: String) async {
        isProcessing = true
        progress = 0
        error = nil
        completedSession = nil

        // Pick per-type tuning. Falls back to defaults for unknown strings.
        let typeEnum = SessionType(rawValue: sessionType.lowercased()) ?? .other
        let cfg = typeEnum.diarizationConfig

        // Fresh diarization stack per import — no state leak between runs and
        // session-type config can take effect for the segment buffer + clusterer.
        let clusterer = OnlineSpeakerClusterer(similarityThreshold: cfg.similarityThreshold)
        let embedder: any SpeakerEmbeddingProvider = (try? CoreMLSpeakerEmbedder())
            ?? MockSpeakerEmbedder(speakerCount: 1)
        let diarizer = DiarizationEngine(embedder: embedder, clusterer: clusterer)
        let analyzer = SessionAnalyzer(clusterer: clusterer)

        do {
            await update("Loading audio file…", 0.10)
            let (samples, duration, _) = try await importer.loadAudioFile(url: url)
            guard duration <= Self.maxDurationSeconds else { throw ImportError.fileTooLarge }

            await update("Detecting speech segments…", 0.25)
            let segments = segmentAudio(samples: samples, config: cfg)

            await update("Identifying speakers…", 0.45)
            var diarized: [DiarizedSegment] = []
            diarized.reserveCapacity(segments.count)
            for segment in segments {
                diarized.append(await diarizer.process(segment))
            }

            await update("Transcribing conversation…", 0.65)
            let transcript = await transcriber.transcribeAll(diarized)

            await update("Building coaching report…", 0.80)
            let sessionID = UUID()
            let raw = AudioPipelineCoordinator.RawSessionData(
                segments: segments,
                totalDuration: duration,
                startTime: Date()
            )
            await analyzer.analyze(
                sessionID: sessionID,
                sessionName: sessionName,
                sessionType: sessionType,
                rawData: raw,
                transcript: transcript,
                diarizedSegments: diarized
            )

            await update("Saving…", 0.95)
            if AudioStorageManager.shared.saveAudioEnabled {
                _ = try? await AudioStorageManager.shared.save(samples: samples, sessionID: sessionID)
            }

            // Hand the navigation a Session value once analysis is done.
            completedSession = analyzer.completedSession
            progress = 1.0
            isProcessing = false
        } catch {
            self.error = error.localizedDescription
            isProcessing = false
        }
    }

    // MARK: - VAD pass

    /// Runs the same VAD + segment buffer used in the live pipeline across
    /// the whole imported audio, returning the resulting speech segments.
    private func segmentAudio(samples: [Float], config: DiarizationConfig) -> [SpeechSegment] {
        var vad = VoiceActivityDetector()
        let buffer = SpeechSegmentBuffer(
            minSamples: config.minSegmentSamples,
            maxSamples: config.maxSegmentSamples
        )
        var segments: [SpeechSegment] = []
        buffer.onSegmentReady = { segments.append($0) }

        let frameSize = AudioCaptureEngine.frameSize // 320 = 20 ms @ 16 kHz
        var offset = 0
        while offset + frameSize <= samples.count {
            let frame = Array(samples[offset ..< offset + frameSize])
            let state = vad.processingFrame(frame)
            buffer.append(samples: frame, state: state)
            offset += frameSize
        }
        return segments
    }

    // MARK: -

    private func update(_ step: String, _ progress: Double) async {
        await MainActor.run {
            self.processingStep = step
            self.progress = progress
        }
    }
}
