import SwiftUI

struct TranscriptLineRow: View {
    let line: TranscriptLine
    /// Pass `nil` when the session has no audio saved (no tap-to-seek available).
    var playerVM: AudioPlayerViewModel? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(SpeakerColor.color(for: line.speakerIndex))
                .frame(width: 8, height: 8)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("Speaker \(line.speakerIndex + 1)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(format(line.timestampSeconds))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                    if playerVM != nil {
                        Image(systemName: "play.circle")
                            .font(.caption2)
                            .foregroundStyle(Color(hex: "7F77DD"))
                    }
                }
                Text(line.text)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            playerVM?.seekTo(seconds: line.timestampSeconds)
        }
    }

    private func format(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
