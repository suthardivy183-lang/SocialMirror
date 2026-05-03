import CoreData
import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = ImportSessionViewModel()

    @State private var showFilePicker = false
    @State private var sessionName = ""
    @State private var sessionType = "Call"
    @State private var selectedURL: URL?

    var body: some View {
        NavigationStack {
            Group {
                if vm.isProcessing {
                    ImportProcessingView(step: vm.processingStep, progress: vm.progress)
                } else {
                    importForm
                }
            }
            .navigationTitle("Import Recording")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !vm.isProcessing {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: AudioImporter.supportedTypes,
                allowsMultipleSelection: false
            ) { result in
                if case let .success(urls) = result, let url = urls.first {
                    selectedURL = url
                    if sessionName.isEmpty {
                        sessionName = url.deletingPathExtension().lastPathComponent
                    }
                }
            }
            .alert(
                "Import failed",
                isPresented: Binding(
                    get: { vm.error != nil },
                    set: { if !$0 { vm.error = nil } }
                ),
                actions: { Button("OK", role: .cancel) { vm.error = nil } },
                message: { Text(vm.error ?? "") }
            )
            .navigationDestination(item: $vm.completedSession) { session in
                SessionDetailLoader(sessionID: session.id)
            }
        }
        .tint(AppColor.primary)
    }

    @ViewBuilder
    private var importForm: some View {
        Form {
            Section("Session details") {
                TextField("Name (e.g. Sales call – Acme)", text: $sessionName)
                Picker("Type", selection: $sessionType) {
                    Text("Call").tag("Call")
                    Text("Meeting").tag("Meeting")
                    Text("Interview").tag("Interview")
                    Text("Negotiation").tag("Negotiation")
                    Text("Other").tag("Other")
                }
            }

            Section("Choose audio source") {
                Button {
                    showFilePicker = true
                } label: {
                    Label("Import from Files", systemImage: "folder")
                }
                Button {
                    // Voice Memos exports are .m4a in the Files browser; this opens
                    // the same picker — Files makes Voice Memos discoverable as a Source.
                    showFilePicker = true
                } label: {
                    Label("Import from Voice Memos", systemImage: "mic.circle")
                }
            }

            if let url = selectedURL {
                Section("Selected file") {
                    HStack {
                        Image(systemName: "waveform")
                            .foregroundStyle(AppColor.primary)
                        Text(url.lastPathComponent)
                            .font(.subheadline)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    if let estimate = estimatedTime(for: url) {
                        Label(estimate, systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button(action: analyzeImport) {
                        Text("Analyze recording")
                            .frame(maxWidth: .infinity)
                            .fontWeight(.medium)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppColor.primary)
                    .disabled(sessionName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            Section {
                EmptyView()
            } footer: {
                Text("Supports: m4a, mp3, wav, aac, opus\nMaximum length: 3 hours\nAll processing happens on your device.")
                    .font(.caption)
            }
        }
    }

    private func analyzeImport() {
        guard let url = selectedURL else { return }
        Task {
            await vm.process(url: url, sessionName: sessionName, sessionType: sessionType)
        }
    }

    /// Rough analyze-time estimate (≈ 0.3× realtime on A15 and newer).
    private func estimatedTime(for url: URL) -> String? {
        guard let duration = AudioImporter.probeDuration(url: url) else { return nil }
        let estimate = duration * 0.3
        let minutes = Int(estimate) / 60
        if minutes < 1 { return "~30 seconds to analyze" }
        return "~\(minutes) minute\(minutes == 1 ? "" : "s") to analyze"
    }
}

// MARK: - Processing screen

struct ImportProcessingView: View {
    let step: String
    let progress: Double

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "waveform.circle")
                .font(.system(size: 56))
                .foregroundStyle(AppColor.primary)
                .symbolEffect(.pulse, options: .repeating)

            Text("Analyzing recording")
                .font(.title3.weight(.medium))

            Text(step)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)

            ProgressView(value: progress)
                .tint(AppColor.primary)
                .padding(.horizontal, 40)

            Text(String(format: "%.0f%%", progress * 100))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()

            Spacer()

            Text("This may take a few minutes\nfor longer recordings")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

// MARK: - Session struct → SessionEntity loader

/// `ImportSessionViewModel` publishes a `Session` struct when analysis is
/// done. The persisted `SessionEntity` lives in Core Data, so we look it up
/// here and hand it to the existing `SessionDetailView`.
struct SessionDetailLoader: View {
    @Environment(\.managedObjectContext) private var ctx
    let sessionID: UUID

    var body: some View {
        if let entity = lookup() {
            SessionDetailView(session: entity)
        } else {
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading session…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

#Preview {
    ImportView()
        .environment(\.managedObjectContext, CoreDataStack.shared.viewContext)
}
