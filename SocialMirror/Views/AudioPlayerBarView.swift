import SwiftUI

struct AudioPlayerBarView: View {
    let sessionID: UUID
    @StateObject private var vm = AudioPlayerViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recording")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 14) {
                Button {
                    vm.togglePlayback()
                } label: {
                    Image(systemName: vm.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 38))
                        .foregroundStyle(Color(hex: "7F77DD"))
                }
                .accessibilityLabel(vm.isPlaying ? "Pause recording" : "Play recording")

                VStack(spacing: 5) {
                    Slider(
                        value: $vm.progress,
                        in: 0 ... 1,
                        onEditingChanged: { editing in
                            if !editing { vm.seek(to: vm.progress) }
                        }
                    )
                    .tint(Color(hex: "7F77DD"))

                    HStack {
                        Text(vm.currentTimeString)
                        Spacer()
                        Text(vm.durationString)
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                }
            }

            HStack {
                if let mb = AudioStorageManager.shared.fileSizeMB(sessionID: sessionID) {
                    Text(String(format: "%.1f MB", mb))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button("Delete audio") {
                    vm.deleteAudio(sessionID: sessionID)
                }
                .font(.caption2)
                .foregroundStyle(.red)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.separator), lineWidth: 0.5)
                )
        )
        .onAppear { vm.load(sessionID: sessionID) }
    }
}
