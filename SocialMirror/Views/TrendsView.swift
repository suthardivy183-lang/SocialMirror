import Charts
import CoreData
import SwiftUI

struct TrendsView: View {
    enum Range: String, CaseIterable, Identifiable {
        case last7 = "Last 7"
        case last30 = "Last 30"
        case all = "All"
        var id: String { rawValue }
    }

    @State private var range: Range = .last30

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \SessionEntity.startTime, ascending: true)]
    )
    private var sessions: FetchedResults<SessionEntity>

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Range", selection: $range) {
                    ForEach(Range.allCases) { r in Text(r.rawValue).tag(r) }
                }
                .pickerStyle(.segmented)

                if filtered.isEmpty {
                    Text("Record at least one session to see trends.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 60)
                } else {
                    PatternBadgesRow(sessions: filtered)
                    TalkTimeChart(points: talkTimePoints)
                    HedgeChart(points: hedgePoints)
                    InterruptionChart(points: interruptionPoints)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Trends")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Filtering

    private var filtered: [SessionEntity] {
        let all = Array(sessions)
        switch range {
        case .all: return all
        case .last7: return Array(all.suffix(7))
        case .last30: return Array(all.suffix(30))
        }
    }

    // MARK: - Data points

    private var talkTimePoints: [TrendPoint] {
        filtered.compactMap { s in
            guard let date = s.startTime, let user = userSpeaker(of: s) else { return nil }
            return TrendPoint(date: date, value: user.talkTimeRatio)
        }
    }

    private var hedgePoints: [TrendPoint] {
        filtered.compactMap { s in
            guard let date = s.startTime, let user = userSpeaker(of: s) else { return nil }
            return TrendPoint(date: date, value: Double(user.hedgeWordCount))
        }
    }

    private var interruptionPoints: [TrendPoint] {
        filtered.compactMap { s in
            guard let date = s.startTime, let user = userSpeaker(of: s) else { return nil }
            return TrendPoint(date: date, value: Double(user.interruptionCount))
        }
    }

    private func userSpeaker(of session: SessionEntity) -> SpeakerEntity? {
        let speakers = (session.speakers as? Set<SpeakerEntity> ?? []).sorted { $0.speakerIndex < $1.speakerIndex }
        return speakers.first
    }
}

struct TrendPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

// MARK: - Charts

private struct TalkTimeChart: View {
    let points: [TrendPoint]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your talk-time ratio").font(.headline)
            Chart(points) {
                LineMark(x: .value("When", $0.date), y: .value("Ratio", $0.value))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(AppColor.primary)
                PointMark(x: .value("When", $0.date), y: .value("Ratio", $0.value))
                    .foregroundStyle(AppColor.primary)
            }
            .chartYScale(domain: 0 ... 1)
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel { Text("\(Int((value.as(Double.self) ?? 0) * 100))%") }
                }
            }
            .frame(height: 180)
        }
        .cardStyle()
    }
}

private struct HedgeChart: View {
    let points: [TrendPoint]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Hedge words per session").font(.headline)
            Chart(points) {
                BarMark(x: .value("When", $0.date), y: .value("Hedges", $0.value))
                    .foregroundStyle(AppColor.speaker(3))
            }
            .frame(height: 180)
        }
        .cardStyle()
    }
}

private struct InterruptionChart: View {
    let points: [TrendPoint]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Interruption rate").font(.headline)
            Chart(points) {
                LineMark(x: .value("When", $0.date), y: .value("Count", $0.value))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(AppColor.recording)
                PointMark(x: .value("When", $0.date), y: .value("Count", $0.value))
                    .foregroundStyle(AppColor.recording)
            }
            .frame(height: 180)
        }
        .cardStyle()
    }
}

// MARK: - Pattern badges

private struct PatternBadgesRow: View {
    let sessions: [SessionEntity]

    var body: some View {
        let badges = derived
        if !badges.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(badges) { badge in
                        Text(badge.label).pillStyle(color: badge.color)
                    }
                }
            }
        }
    }

    private var derived: [PatternBadge] {
        var out: [PatternBadge] = []

        // Talk-time > 65% in 3+ consecutive sessions.
        let userTalk = sessions.compactMap { s -> Double? in
            (s.speakers as? Set<SpeakerEntity> ?? [])
                .sorted { $0.speakerIndex < $1.speakerIndex }
                .first?.talkTimeRatio
        }
        if hasConsecutive(userTalk, count: 3, where: { $0 > 0.65 }) {
            out.append(PatternBadge(label: "You tend to dominate", color: AppColor.recording))
        }

        // Hedge count strictly decreasing across last ≥3 sessions.
        let hedges: [Int] = sessions.compactMap { s in
            (s.speakers as? Set<SpeakerEntity> ?? [])
                .sorted { $0.speakerIndex < $1.speakerIndex }
                .first.map { Int($0.hedgeWordCount) }
        }
        if hedges.count >= 3, isStrictlyDecreasing(Array(hedges.suffix(3))) {
            out.append(PatternBadge(label: "Confidence improving ↑", color: AppColor.speaker(1)))
        }

        // Interruptions > 5 in last 3 sessions.
        let recentInterruptions = sessions.suffix(3).compactMap { s -> Int? in
            (s.speakers as? Set<SpeakerEntity> ?? [])
                .sorted { $0.speakerIndex < $1.speakerIndex }
                .first.map { Int($0.interruptionCount) }
        }
        if recentInterruptions.count == 3, recentInterruptions.allSatisfy({ $0 > 5 }) {
            out.append(PatternBadge(label: "Interrupting more lately", color: AppColor.speaker(2)))
        }

        return out
    }

    private func hasConsecutive<T>(_ arr: [T], count: Int, where pred: (T) -> Bool) -> Bool {
        var run = 0
        for v in arr {
            run = pred(v) ? run + 1 : 0
            if run >= count { return true }
        }
        return false
    }

    private func isStrictlyDecreasing<T: Comparable>(_ arr: [T]) -> Bool {
        zip(arr, arr.dropFirst()).allSatisfy { $0 > $1 }
    }
}

private struct PatternBadge: Identifiable {
    let id = UUID()
    let label: String
    let color: Color
}

#Preview {
    NavigationStack { TrendsView() }
        .environment(\.managedObjectContext, CoreDataStack.shared.viewContext)
}
