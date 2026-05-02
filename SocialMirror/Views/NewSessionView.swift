import AVFoundation
import SwiftUI

struct NewSessionView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(UserDefaultsKey.saveAudioEnabled) private var saveAudioEnabled = true

    @State private var sessionName: String = ""
    @State private var selectedType: SessionType = .meeting
    @State private var permission: AVAudioApplication.recordPermission = AVAudioApplication.shared.recordPermission
    @State private var presentLive = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Session name") {
                    TextField("e.g. Quarterly review", text: $sessionName)
                        .focused($nameFocused)
                }

                Section("Type") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
                        ForEach(SessionType.allCases) { type in
                            TypeTile(type: type, selected: type == selectedType) {
                                selectedType = type
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                if permission != .granted {
                    Section("Microphone") {
                        PermissionPrompt(permission: $permission)
                    }
                }

                if saveAudioEnabled,
                   let available = AudioStorageManager.shared.availableStorageMB(),
                   available < 500 {
                    Section {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(String(format: "%.0f MB available. Audio saving may be limited.", available))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Button {
                        presentLive = true
                    } label: {
                        HStack {
                            Spacer()
                            Image(systemName: "record.circle")
                            Text("Start Recording").bold()
                            Spacer()
                        }
                        .padding(.vertical, 6)
                    }
                    .disabled(sessionName.trimmingCharacters(in: .whitespaces).isEmpty || permission != .granted)
                }
            }
            .navigationTitle("New Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $presentLive) {
                LiveSessionView(
                    sessionName: sessionName.trimmingCharacters(in: .whitespaces),
                    sessionType: selectedType,
                    onClose: { dismiss() }
                )
            }
            .onAppear { nameFocused = true }
        }
        .tint(AppColor.primary)
    }
}

private struct TypeTile: View {
    let type: SessionType
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: type.symbol)
                    .font(.title3)
                Text(type.label)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(selected ? AppColor.primary.opacity(0.18) : Color(.tertiarySystemFill))
            .foregroundStyle(selected ? AppColor.primary : .primary)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.card)
                    .stroke(selected ? AppColor.primary : .clear, lineWidth: 1.2)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct PermissionPrompt: View {
    @Binding var permission: AVAudioApplication.recordPermission

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Social Mirror needs the microphone to analyze conversations on-device.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if permission == .denied {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("Open Settings", systemImage: "gearshape")
                }
            } else {
                Button {
                    Task {
                        let granted = await AVAudioApplication.requestRecordPermission()
                        await MainActor.run {
                            permission = granted ? .granted : .denied
                        }
                    }
                } label: {
                    Label("Allow Microphone Access", systemImage: "mic")
                }
            }
        }
    }
}

#Preview {
    NewSessionView()
}
