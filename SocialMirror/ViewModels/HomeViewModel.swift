import Combine
import CoreData
import Foundation

/// Aggregated trend signals computed from the session history.
struct TrendsData: Sendable {
    let talkTimeHistory: [(date: Date, ratio: Double)]
    let hedgeWordHistory: [(date: Date, count: Int)]
    let interruptionHistory: [(date: Date, count: Int)]
    let patterns: [String]
}

/// Spec-compatible view-model. The current `HomeView` uses `@FetchRequest`
/// directly (idiomatic SwiftUI), so this VM is here primarily to expose the
/// trend-detection logic and a programmatic delete API.
@MainActor
final class HomeViewModel: ObservableObject {
    @Published var sessions: [Session] = []

    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext = CoreDataStack.shared.viewContext) {
        self.context = context
        refresh()
    }

    func refresh() {
        let req = NSFetchRequest<SessionEntity>(entityName: "SessionEntity")
        req.sortDescriptors = [NSSortDescriptor(keyPath: \SessionEntity.startTime, ascending: false)]
        let entities = (try? context.fetch(req)) ?? []
        sessions = entities.map { entity in
            Session(
                id: entity.id ?? UUID(),
                name: entity.name ?? "",
                sessionType: entity.sessionType ?? "",
                startTime: entity.startTime ?? Date(),
                endTime: entity.endTime,
                speakerCount: Int(entity.speakerCount),
                durationSeconds: entity.durationSeconds
            )
        }
    }

    func deleteSession(_ session: Session) {
        let req = NSFetchRequest<SessionEntity>(entityName: "SessionEntity")
        req.predicate = NSPredicate(format: "id == %@", session.id as CVarArg)
        req.fetchLimit = 1
        guard let entity = (try? context.fetch(req))?.first else { return }
        try? AudioStorageManager.shared.delete(sessionID: session.id)
        context.delete(entity)
        try? context.save()
        refresh()
    }

    // MARK: - Trends

    func fetchTrends() -> TrendsData {
        let req = NSFetchRequest<SessionEntity>(entityName: "SessionEntity")
        req.sortDescriptors = [NSSortDescriptor(keyPath: \SessionEntity.startTime, ascending: true)]
        let entities = (try? context.fetch(req)) ?? []

        var talk: [(Date, Double)] = []
        var hedge: [(Date, Int)] = []
        var interrupt: [(Date, Int)] = []

        for s in entities {
            guard let date = s.startTime,
                  let user = (s.speakers as? Set<SpeakerEntity> ?? [])
                    .sorted(by: { $0.speakerIndex < $1.speakerIndex })
                    .first
            else { continue }
            talk.append((date, user.talkTimeRatio))
            hedge.append((date, Int(user.hedgeWordCount)))
            interrupt.append((date, Int(user.interruptionCount)))
        }

        return TrendsData(
            talkTimeHistory: talk,
            hedgeWordHistory: hedge,
            interruptionHistory: interrupt,
            patterns: detectPatterns(talk: talk, hedge: hedge, interrupt: interrupt)
        )
    }

    private func detectPatterns(
        talk: [(Date, Double)],
        hedge: [(Date, Int)],
        interrupt: [(Date, Int)]
    ) -> [String] {
        var out: [String] = []

        let talkValues = talk.map(\.1)
        if hasConsecutive(talkValues, count: 3, where: { $0 > 0.65 }) {
            out.append("You tend to dominate")
        }

        let hedgeValues = hedge.map(\.1)
        if hedgeValues.count >= 3, isStrictlyDecreasing(Array(hedgeValues.suffix(3))) {
            out.append("Confidence improving ↑")
        }

        let recentInt = interrupt.suffix(3).map(\.1)
        if recentInt.count == 3, recentInt.allSatisfy({ $0 > 5 }) {
            out.append("Interrupting more lately")
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
