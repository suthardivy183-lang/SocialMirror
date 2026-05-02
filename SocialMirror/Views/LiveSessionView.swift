import CoreData
import SwiftUI

struct LiveSessionView: View {
    let sessionName: String
    let sessionType: SessionType
    let onClose: () -> Void

    @StateObject private var store: LiveSessionStore

    init(sessionName: String, sessionType: SessionType, onClose: @escaping () -> Void) {
        self.sessionName = sessionName
        self.sessionType = sessionType
        self.onClose = onClose
        _store = StateObject(wrappedValue: LiveSessionStore(sessionName: sessionName, sessionType: sessionType))
    }

    var body: some View {
        ZStack {
            switch store.phase {
            case .recording:
                RecordingScreen(store: store)
            case .processing:
                ProcessingView(status: store.analyzer.status)
            case .done(let id):
                CompletedScreen(sessionID: id, onClose: onClose)
            }
        }
        .preferredColorScheme(.dark)
        .task { await store.start() }
    }
}

// MARK: - Recording

private struct RecordingScreen: View {
    @ObservedObject var store: LiveSessionStore

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                header

                Spacer()

                Waveform(level: store.pipeline.currentLevel)
                    .frame(height: 120)
                    .padding(.horizontal)

                Timer(elapsed: store.elapsedSeconds)

                RecordingDot()

                Spacer()

                if store.diarizer.detectedSpeakerCount > 0 {
                    SpeakerStrip(diarizer: store.diarizer)
                        .padding(.horizontal)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                Spacer()

                StopButton {
                    Task { await store.stop() }
                }
                .padding(.horizontal, 24)

                Text("Audio deleted after processing · stays on device")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.bottom, 8)
            }
            .padding(.top, 24)
        }
        .alert(store.startError ?? "", isPresented: Binding(
            get: { store.startError != nil },
            set: { if !$0 { store.startError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text(store.sessionName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            SessionTypeBadge(type: store.sessionType.rawValue)
        }
    }
}

private struct Waveform: View {
    let level: Float
    static let bars: Int = 20

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { _ in
            HStack(spacing: 4) {
                ForEach(0 ..< Self.bars, id: \.self) { i in
                    Capsule()
                        .fill(AppColor.primary)
                        .frame(width: 6, height: barHeight(i))
                }
            }
            .frame(maxWidth: .infinity)
            .animation(.easeOut(duration: 0.1), value: level)
        }
    }

    private func barHeight(_ i: Int) -> CGFloat {
        // Boost the visual signal — RMS rarely passes 0.3 even when loud.
        let amp = CGFloat(min(1, max(0, level * 8)))
        // Pseudo-random shape per bar so they move organically.
        let phase = sin(Date().timeIntervalSinceReferenceDate * 4 + Double(i) * 0.6)
        let scale = 0.4 + 0.6 * (CGFloat(phase) * 0.5 + 0.5)
        return max(8, amp * 110 * scale)
    }
}

private struct Timer: View {
    let elapsed: TimeInterval
    var body: some View {
        Text(format(elapsed))
            .font(.system(size: 56, weight: .light, design: .monospaced))
            .foregroundStyle(.white)
            .monospacedDigit()
    }

    private func format(_ s: TimeInterval) -> String {
        let total = Int(s)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

private struct RecordingDot: View {
    @State private var pulsing = false
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(AppColor.recording)
                .frame(width: 10, height: 10)
                .opacity(pulsing ? 1 : 0.3)
                .animation(.easeInOut(duration: 0.9).repeatForever(), value: pulsing)
            Text("Recording")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.85))
        }
        .onAppear { pulsing = true }
    }
}

private struct SpeakerStrip: View {
    @ObservedObject var diarizer: DiarizationEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(diarizer.detectedSpeakerCount) speakers detected")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.7))

            VStack(spacing: 6) {
                ForEach(orderedIDs, id: \.self) { id in
                    HStack(spacing: 8) {
                        Circle().fill(AppColor.speaker(id)).frame(width: 8, height: 8)
                        TalkBar(value: ratio(for: id), color: AppColor.speaker(id))
                        Text(timeLabel(diarizer.speakerTalkTimes[id] ?? 0))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }
        }
    }

    private var orderedIDs: [Int] {
        diarizer.speakerTalkTimes.keys.sorted()
    }

    private func ratio(for id: Int) -> Double {
        let total = diarizer.speakerTalkTimes.values.reduce(0, +)
        guard total > 0 else { return 0 }
        return (diarizer.speakerTalkTimes[id] ?? 0) / total
    }

    private func timeLabel(_ s: TimeInterval) -> String {
        let total = Int(s)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct TalkBar: View {
    let value: Double
    let color: Color
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.08))
                RoundedRectangle(cornerRadius: 4)
                    .fill(color)
                    .frame(width: geo.size.width * CGFloat(value))
                    .animation(.easeInOut(duration: 0.3), value: value)
            }
        }
        .frame(height: 8)
    }
}

private struct StopButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: "stop.circle.fill")
                Text("Stop & Analyze").bold()
            }
            .frame(maxWidth: .infinity)
            .font(.body.weight(.semibold))
            .padding(.vertical, 16)
            .background(.white)
            .foregroundStyle(.black)
            .clipShape(Capsule())
        }
    }
}

// MARK: - Completed bridge

private struct CompletedScreen: View {
    let sessionID: UUID
    let onClose: () -> Void

    @Environment(\.managedObjectContext) private var ctx

    var body: some View {
        Group {
            if let session = lookup() {
                NavigationStack {
                    SessionDetailView(session: session)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { onClose() }
                            }
                        }
                }
            } else {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.ignoresSafeArea())
                    .preferredColorScheme(.dark)
            }
        }
    }

    private func lookup() -> SessionEntity? {
        let req = NSFetchRequest<SessionEntity>(entityName: "SessionEntity")
        req.predicate = NSPredicate(format: "id == %@", sessionID as CVarArg)
        req.fetchLimit = 1
        return (try? ctx.fetch(req))?.first
    }
}
