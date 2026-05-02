import CoreData
import SwiftUI

struct SettingsView: View {
    @Environment(\.managedObjectContext) private var ctx
    @State private var saveAudio: Bool = AudioStorageManager.shared.saveAudioEnabled
    @State private var healthKitEnabled: Bool = false
    @State private var saveTranscripts: Bool = true
    @State private var howItWorksExpanded = false
    @State private var showDeleteAlert = false

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \SpeakerEntity.speakerIndex, ascending: true)]
    )
    private var allSpeakers: FetchedResults<SpeakerEntity>

    var body: some View {
        Form {
            Section("Speakers") {
                if allSpeakers.isEmpty {
                    Text("Speakers will appear here after your first session.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(speakerGroups, id: \.sessionID) { group in
                        DisclosureGroup(group.sessionName) {
                            ForEach(group.speakers, id: \.objectID) { speaker in
                                SpeakerRenameRow(speaker: speaker)
                            }
                        }
                    }
                }
            }

            Section("Privacy") {
                Toggle("Save transcripts", isOn: $saveTranscripts)
                Toggle("Save audio recordings", isOn: $saveAudio)
                    .onChange(of: saveAudio) { _, new in
                        AudioStorageManager.shared.saveAudioEnabled = new
                    }
                Toggle("HealthKit integration", isOn: $healthKitEnabled)

                Button(role: .destructive) {
                    showDeleteAlert = true
                } label: {
                    Label("Delete all data", systemImage: "trash")
                }
            }

            Section("About") {
                DisclosureGroup("How it works", isExpanded: $howItWorksExpanded) {
                    Text(howItWorksText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                NavigationLink("Privacy policy") {
                    PrivacyPolicy()
                }
                LabeledContent("Version", value: appVersion)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete all data?", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { deleteEverything() }
        } message: {
            Text("This permanently removes all sessions, transcripts, and audio.")
        }
    }

    // MARK: - Helpers

    private struct SessionGroup {
        let sessionID: NSManagedObjectID
        let sessionName: String
        let speakers: [SpeakerEntity]
    }

    private var speakerGroups: [SessionGroup] {
        let bySession = Dictionary(grouping: allSpeakers) { $0.session?.objectID ?? NSManagedObjectID() }
        return bySession.map { id, speakers in
            let name = speakers.first?.session?.name ?? "Untitled"
            return SessionGroup(
                sessionID: id,
                sessionName: name,
                speakers: speakers.sorted { $0.speakerIndex < $1.speakerIndex }
            )
        }.sorted { $0.sessionName < $1.sessionName }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    private var howItWorksText: String {
        """
        Social Mirror records audio on-device and analyzes it using:
        • A voice-activity detector that splits speech into segments
        • An ECAPA-TDNN model that turns each segment into a 192-dim speaker embedding
        • Online cosine clustering that groups embeddings into speakers
        • Acoustic + linguistic feature extraction (pitch, hedges, interruptions)
        • A rules-based coaching report tailored to your patterns
        Nothing leaves your device.
        """
    }

    private func deleteEverything() {
        AudioStorageManager.shared.deleteAll()
        ["SessionEntity", "SpeakerEntity", "TranscriptLineEntity"].forEach { name in
            let req = NSFetchRequest<NSFetchRequestResult>(entityName: name)
            let delete = NSBatchDeleteRequest(fetchRequest: req)
            _ = try? ctx.execute(delete)
        }
        try? ctx.save()
    }
}

private struct SpeakerRenameRow: View {
    @ObservedObject var speaker: SpeakerEntity
    @State private var name: String = ""

    var body: some View {
        HStack {
            Circle()
                .fill(AppColor.speaker(Int(speaker.speakerIndex)))
                .frame(width: 10, height: 10)
            TextField("Speaker \(speaker.speakerIndex + 1)", text: $name)
                .onAppear { name = speaker.assignedName ?? "" }
                .onSubmit {
                    speaker.assignedName = name.isEmpty ? nil : name
                    try? speaker.managedObjectContext?.save()
                }
        }
    }
}

private struct PrivacyPolicy: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Privacy")
                    .font(.title.weight(.bold))
                Text("""
                Social Mirror is a fully on-device app. We do not run any servers, do not collect analytics, and do not transmit any audio, transcripts, or scores off your device.

                The microphone is used only while a session is actively recording. Audio is processed in-memory by an on-device speech model and an on-device speaker embedding model. If you opt to save the recording (Settings → Privacy → Save audio recordings), the file is encrypted with iOS Data Protection (`completeUnlessOpen`) and lives in your app's sandbox until you delete it.

                Sessions, speaker stats, and transcripts are stored in an encrypted Core Data store inside your app's sandbox. They never leave your device.

                You can delete everything at any time from Settings → Privacy → Delete all data.
                """)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { SettingsView() }
        .environment(\.managedObjectContext, CoreDataStack.shared.viewContext)
}
