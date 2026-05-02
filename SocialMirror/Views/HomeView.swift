import CoreData
import SwiftUI

struct HomeView: View {
    @Environment(\.managedObjectContext) private var ctx

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \SessionEntity.startTime, ascending: false)],
        animation: .default
    )
    private var sessions: FetchedResults<SessionEntity>

    @State private var showNewSession = false
    @State private var pendingDelete: SessionEntity?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Group {
                    if sessions.isEmpty {
                        EmptyStateView()
                    } else {
                        SessionList(sessions: sessions, onDelete: { pendingDelete = $0 })
                    }
                }

                StartButton(action: { showNewSession = true })
                    .padding(.bottom, 24)
            }
            .navigationTitle("Sessions")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink(destination: TrendsView()) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showNewSession) {
                NewSessionView()
            }
            .alert(
                "Delete this session?",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                )
            ) {
                Button("Cancel", role: .cancel) { pendingDelete = nil }
                Button("Delete", role: .destructive) {
                    if let target = pendingDelete { delete(target) }
                    pendingDelete = nil
                }
            } message: {
                Text("This permanently removes the session and any associated audio.")
            }
        }
        .tint(AppColor.primary)
    }

    private func delete(_ session: SessionEntity) {
        if let id = session.id {
            try? AudioStorageManager.shared.delete(sessionID: id)
        }
        ctx.delete(session)
        try? ctx.save()
    }
}

private struct SessionList: View {
    let sessions: FetchedResults<SessionEntity>
    let onDelete: (SessionEntity) -> Void

    var body: some View {
        List {
            ForEach(sessions) { session in
                NavigationLink(destination: SessionDetailView(session: session)) {
                    SessionRow(session: session)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { onDelete(session) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .safeAreaPadding(.bottom, 80)
    }
}

private struct SessionRow: View {
    @ObservedObject var session: SessionEntity

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(session.name ?? "Untitled")
                    .font(.headline)
                Spacer()
                SessionTypeBadge(type: session.sessionType ?? "other")
            }
            HStack(spacing: 10) {
                Text(formatted(session.startTime))
                Text("•")
                Text(duration(session.durationSeconds))
                Spacer()
                SpeakerDots(count: max(0, Int(session.speakerCount)))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func formatted(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

private struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "waveform.circle")
                .font(.system(size: 80))
                .foregroundStyle(AppColor.primary.opacity(0.7))
            Text("No sessions yet")
                .font(.title2.weight(.semibold))
            Text("Tap below to record your first session.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct StartButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: "mic.fill")
                Text("Start Session").bold()
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
            .background(AppColor.primary)
            .clipShape(Capsule())
            .shadow(color: AppColor.primary.opacity(0.3), radius: 12, y: 4)
        }
        .accessibilityLabel("Start a new session")
    }
}

#Preview {
    HomeView()
        .environment(\.managedObjectContext, CoreDataStack.shared.viewContext)
        .environmentObject(CoreDataStack.shared)
}
