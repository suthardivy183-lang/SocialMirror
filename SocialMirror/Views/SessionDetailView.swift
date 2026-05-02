import CoreData
import SwiftUI

struct SessionDetailView: View {
    @ObservedObject var session: SessionEntity
    @State private var transcriptExpanded = false
    @State private var transcriptFilter = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HeaderSection(session: session)
                RadarSection(speakers: speakers)
                StatsGrid(speakers: speakers, userID: 0)
                DominanceTimeline(session: session, lines: transcriptLines)
                CoachingSection(report: report)
                TranscriptSection(
                    lines: transcriptLines,
                    expanded: $transcriptExpanded,
                    filter: $transcriptFilter
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Session")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Derived

    private var speakers: [SpeakerFeatureSet] {
        let entities = (session.speakers as? Set<SpeakerEntity> ?? [])
            .sorted { $0.speakerIndex < $1.speakerIndex }
        return entities.map { SpeakerFeatureSet(entity: $0) }
    }

    private var transcriptLines: [TranscriptLineEntity] {
        (session.lines as? Set<TranscriptLineEntity> ?? [])
            .sorted { $0.timestampSeconds < $1.timestampSeconds }
    }

    private var report: CoachingReport {
        CoachingReportGenerator.generate(
            for: session.id ?? UUID(),
            userSpeakerID: 0,
            speakers: speakers
        )
    }
}

// MARK: - Sections

private struct HeaderSection: View {
    @ObservedObject var session: SessionEntity
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(session.name ?? "Untitled")
                        .font(.title2.weight(.bold))
                    HStack(spacing: 8) {
                        SessionTypeBadge(type: session.sessionType ?? "other")
                        Text(formatted(session.startTime))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("•").foregroundStyle(.secondary)
                        Text(duration(session.durationSeconds))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            HStack(spacing: 8) {
                SpeakerDots(count: max(0, Int(session.speakerCount)))
                Text("\(session.speakerCount) speakers")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .cardStyle()
    }

    private func formatted(_ d: Date?) -> String {
        guard let d else { return "" }
        return d.formatted(date: .abbreviated, time: .shortened)
    }

    private func duration(_ s: Double) -> String {
        let total = Int(s)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct RadarSection: View {
    let speakers: [SpeakerFeatureSet]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Social X-ray")
                .font(.headline)
            RadarChart(speakers: radarSpeakers)
                .frame(height: 280)
        }
        .cardStyle()
    }

    private var radarSpeakers: [RadarSpeaker] {
        let maxInterruptions = max(1, speakers.map(\.interruptionCount).max() ?? 1)
        let maxQuestions = max(1, speakers.map(\.questionCount).max() ?? 1)
        return speakers.map { s in
            RadarSpeaker(
                id: s.speakerID,
                label: "Speaker \(s.speakerID + 1)",
                color: AppColor.speaker(s.speakerID),
                values: [
                    s.talkTimeRatio,
                    Double(s.dominanceScore),
                    Double(s.confidenceScore),
                    Double(s.questionCount) / Double(maxQuestions),
                    Double(s.interruptionCount) / Double(maxInterruptions),
                ]
            )
        }
    }
}

private struct StatsGrid: View {
    let speakers: [SpeakerFeatureSet]
    let userID: Int

    private var user: SpeakerFeatureSet? {
        speakers.first { $0.speakerID == userID } ?? speakers.first
    }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
            StatCard(
                value: "\(Int((user?.talkTimeRatio ?? 0) * 100))%",
                label: "Your talk time",
                attribution: "Speaker \(userID + 1)",
                tint: AppColor.speaker(userID)
            )
            StatCard(
                value: "\(user?.questionCount ?? 0)",
                label: "Questions asked",
                attribution: "Speaker \(userID + 1)",
                tint: AppColor.primary
            )
            StatCard(
                value: "\(user?.hedgeWordCount ?? 0)",
                label: "Hedge words",
                attribution: "Speaker \(userID + 1)",
                tint: Color.orange
            )
            StatCard(
                value: "\(user?.interruptionCount ?? 0)",
                label: "Interruptions",
                attribution: "Speaker \(userID + 1)",
                tint: AppColor.recording
            )
        }
    }
}

private struct StatCard: View {
    let value: String
    let label: String
    let attribution: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title.weight(.bold))
                .foregroundStyle(tint)
            Text(label)
                .font(.subheadline)
            Text(attribution)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

private struct DominanceTimeline: View {
    @ObservedObject var session: SessionEntity
    let lines: [TranscriptLineEntity]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Dominance over time")
                .font(.headline)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(.tertiarySystemFill))
                    HStack(spacing: 0) {
                        ForEach(0 ..< segments.count, id: \.self) { i in
                            Rectangle()
                                .fill(AppColor.speaker(segments[i].speaker))
                                .frame(width: geo.size.width * segments[i].fraction)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    HStack {
                        ForEach([0.25, 0.5, 0.75], id: \.self) { _ in
                            Spacer()
                            Rectangle().fill(Color.white.opacity(0.6)).frame(width: 1)
                        }
                        Spacer()
                    }
                }
            }
            .frame(height: 16)
            HStack {
                Text("0:00")
                Spacer()
                Text(format(session.durationSeconds))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .cardStyle()
    }

    private struct TimelineSegment {
        let speaker: Int
        let fraction: Double
    }

    private var segments: [TimelineSegment] {
        let total = max(1.0, session.durationSeconds)
        guard !lines.isEmpty else {
            return [TimelineSegment(speaker: 0, fraction: 1.0)]
        }
        let sorted = lines.sorted { $0.timestampSeconds < $1.timestampSeconds }
        var result: [TimelineSegment] = []
        for (i, line) in sorted.enumerated() {
            let next = (i + 1 < sorted.count) ? sorted[i + 1].timestampSeconds : total
            let span = max(0, next - line.timestampSeconds)
            result.append(TimelineSegment(speaker: Int(line.speakerIndex), fraction: span / total))
        }
        return result
    }

    private func format(_ s: Double) -> String {
        let total = Int(s)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct CoachingSection: View {
    let report: CoachingReport
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(report.headline)
                .font(.title3.weight(.bold))
            Text(report.insight)
                .font(.body)
                .foregroundStyle(.primary.opacity(0.85))
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text("Try next time")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(report.actionableTip)
                    .font(.body.italic())
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [AppColor.primary.opacity(0.18), AppColor.primary.opacity(0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .stroke(AppColor.primary.opacity(0.3), lineWidth: 0.5)
        )
    }
}

private struct TranscriptSection: View {
    let lines: [TranscriptLineEntity]
    @Binding var expanded: Bool
    @Binding var filter: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.3)) { expanded.toggle() }
            } label: {
                HStack {
                    Text("Transcript")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if expanded {
                if lines.isEmpty {
                    Text("Transcripts will appear here once on-device speech recognition is wired up.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    TextField("Filter…", text: $filter)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(filtered) { line in
                                TranscriptRow(line: line)
                            }
                        }
                    }
                    .frame(maxHeight: 320)
                }
            }
        }
        .cardStyle()
    }

    private var filtered: [TranscriptLineEntity] {
        guard !filter.isEmpty else { return lines }
        return lines.filter { ($0.text ?? "").localizedCaseInsensitiveContains(filter) }
    }
}

private struct TranscriptRow: View {
    @ObservedObject var line: TranscriptLineEntity
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(AppColor.speaker(Int(line.speakerIndex))).frame(width: 8, height: 8).padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("Speaker \(line.speakerIndex + 1)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColor.speaker(Int(line.speakerIndex)))
                    Text(format(line.timestampSeconds))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(line.text ?? "")
                    .font(.subheadline)
            }
        }
    }

    private func format(_ s: Double) -> String {
        let total = Int(s)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - SpeakerEntity → SpeakerFeatureSet

extension SpeakerFeatureSet {
    init(entity: SpeakerEntity) {
        self.init(speakerID: Int(entity.speakerIndex))
        self.totalTalkTime = entity.talkTimeSeconds
        self.talkTimeRatio = entity.talkTimeRatio
        self.turnCount = Int(entity.turnCount)
        self.interruptionCount = Int(entity.interruptionCount)
        self.questionCount = Int(entity.questionCount)
        self.hedgeWordCount = Int(entity.hedgeWordCount)
        self.avgResponseLatencyMs = entity.avgResponseLatencyMs
        self.dominanceScore = entity.dominanceScore
        self.confidenceScore = entity.confidenceScore
        if let data = entity.sentimentArcData {
            self.sentimentArc = data.withUnsafeBytes { buf -> [Float] in
                Array(buf.bindMemory(to: Float.self))
            }
        }
    }
}
