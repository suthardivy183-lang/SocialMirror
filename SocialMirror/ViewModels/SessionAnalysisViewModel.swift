import Combine
import CoreData
import Foundation

/// Spec-compatible wrapper around `SessionAnalyzer` (the actual orchestration
/// layer in `/Features`). Lets views written against the
/// `SessionAnalysisViewModel` name bind to the same published state.
@MainActor
final class SessionAnalysisViewModel: ObservableObject {
    @Published var analysisStatus: AnalysisStatus = .idle
    @Published var report: CoachingReport?
    @Published var session: Session?

    private let analyzer: SessionAnalyzer
    private let coreData: CoreDataStack
    private let transcriber = TranscriptionEngine()
    private var cancellables: Set<AnyCancellable> = []

    init(
        analyzer: SessionAnalyzer,
        coreData: CoreDataStack = .shared
    ) {
        self.analyzer = analyzer
        self.coreData = coreData

        analyzer.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.analysisStatus = $0 }
            .store(in: &cancellables)

        analyzer.$report
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.report = $0 }
            .store(in: &cancellables)
    }

    /// Transcribe → analyze → publish. The diarized segments come from the
    /// live recording session's `DiarizationEngine`.
    func runAnalysis(
        sessionID: UUID,
        sessionName: String,
        sessionType: String,
        rawData: AudioPipelineCoordinator.RawSessionData,
        diarizedSegments: [DiarizedSegment]
    ) async {
        let transcript = await transcriber.transcribeAll(diarizedSegments)
        await analyzer.analyze(
            sessionID: sessionID,
            sessionName: sessionName,
            sessionType: sessionType,
            rawData: rawData,
            transcript: transcript,
            diarizedSegments: diarizedSegments
        )
        // Hydrate a Session struct snapshot for views that prefer it over the entity.
        session = Session(
            id: sessionID,
            name: sessionName,
            sessionType: sessionType,
            startTime: rawData.startTime,
            endTime: rawData.startTime.addingTimeInterval(rawData.totalDuration),
            speakerCount: report?.speakerFeatures.count ?? 0,
            durationSeconds: rawData.totalDuration
        )
    }
}
