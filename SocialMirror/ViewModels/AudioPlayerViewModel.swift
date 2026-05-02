import AVFoundation
import Combine
import SwiftUI

@MainActor
final class AudioPlayerViewModel: NSObject, ObservableObject {
    @Published var isPlaying = false
    @Published var progress: Double = 0
    @Published var currentTimeString = "0:00"
    @Published var durationString = "0:00"
    @Published var audioExists = false

    private var player: AVAudioPlayer?
    private var timer: Timer?

    // MARK: - Load

    func load(sessionID: UUID) {
        let url = AudioStorageManager.shared.audioFileURL(for: sessionID)
        guard FileManager.default.fileExists(atPath: url.path) else {
            audioExists = false
            return
        }
        audioExists = true
        player = try? AVAudioPlayer(contentsOf: url)
        player?.delegate = self
        player?.prepareToPlay()
        durationString = formatTime(player?.duration ?? 0)
    }

    // MARK: - Playback

    func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            timer?.invalidate()
        } else {
            try? AVAudioSession.sharedInstance().setCategory(.playback)
            try? AVAudioSession.sharedInstance().setActive(true)
            player.play()
            startTimer()
        }
        isPlaying.toggle()
    }

    func seek(to progress: Double) {
        guard let player else { return }
        player.currentTime = player.duration * progress
        currentTimeString = formatTime(player.currentTime)
    }

    /// Jump to an exact timestamp (e.g. tap on a transcript line).
    func seekTo(seconds: Double) {
        guard let player else { return }
        player.currentTime = seconds
        progress = player.duration > 0 ? seconds / player.duration : 0
        currentTimeString = formatTime(seconds)
        if !isPlaying {
            try? AVAudioSession.sharedInstance().setCategory(.playback)
            try? AVAudioSession.sharedInstance().setActive(true)
            player.play()
            startTimer()
            isPlaying = true
        }
    }

    // MARK: - Delete

    func deleteAudio(sessionID: UUID) {
        player?.stop()
        player = nil
        isPlaying = false
        progress = 0
        timer?.invalidate()
        try? AudioStorageManager.shared.delete(sessionID: sessionID)
        audioExists = false
    }

    // MARK: - Timer

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let player = self.player else { return }
                self.progress = player.duration > 0 ? player.currentTime / player.duration : 0
                self.currentTimeString = self.formatTime(player.currentTime)
            }
        }
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - AVAudioPlayerDelegate

extension AudioPlayerViewModel: @preconcurrency AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_: AVAudioPlayer, successfully _: Bool) {
        isPlaying = false
        progress = 0
        currentTimeString = "0:00"
        timer?.invalidate()
    }
}
