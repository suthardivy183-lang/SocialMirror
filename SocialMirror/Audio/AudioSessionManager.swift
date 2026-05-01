import AVFoundation
import Foundation
import os

/// Configures `AVAudioSession` for measurement-grade speech capture and
/// reacts to interruptions / route changes so the pipeline can pause cleanly.
nonisolated final class AudioSessionManager: @unchecked Sendable {
    private static let log = Logger(subsystem: "com.divy.SocialMirror", category: "AudioSession")

    /// Fired when the OS interrupts capture (phone call, Siri, etc.).
    var onInterruptionBegan: (() -> Void)?
    /// Fired when interruption ends. Caller decides whether to resume.
    var onInterruptionEnded: (() -> Void)?
    /// Fired when audio route changes (headphones plugged/unplugged, BT switch).
    var onRouteChanged: ((AVAudioSession.RouteChangeReason) -> Void)?

    private var observers: [NSObjectProtocol] = []

    init() {
        registerObservers()
    }

    deinit {
        for token in observers {
            NotificationCenter.default.removeObserver(token)
        }
    }

    // MARK: - Permission

    /// Request microphone permission. Returns `true` if granted.
    func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    var permissionStatus: AVAudioApplication.recordPermission {
        AVAudioApplication.shared.recordPermission
    }

    // MARK: - Activation

    func activate() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .record,
            mode: .measurement,
            options: [.allowBluetoothHFP, .allowBluetoothA2DP]
        )
        try session.setActive(true, options: [])
        Self.log.info("AVAudioSession activated (record/measurement)")
    }

    func deactivate() throws {
        try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        Self.log.info("AVAudioSession deactivated")
    }

    // MARK: - Notifications

    private func registerObservers() {
        let center = NotificationCenter.default

        let interrupt = center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            self?.handleInterruption(note)
        }
        observers.append(interrupt)

        let route = center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            self?.handleRouteChange(note)
        }
        observers.append(route)
    }

    private func handleInterruption(_ note: Notification) {
        guard let info = note.userInfo,
              let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw)
        else { return }

        switch type {
        case .began:
            Self.log.info("Audio session interruption began")
            onInterruptionBegan?()
        case .ended:
            Self.log.info("Audio session interruption ended")
            onInterruptionEnded?()
        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ note: Notification) {
        guard let info = note.userInfo,
              let raw = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw)
        else { return }

        Self.log.info("Audio route changed: \(raw, privacy: .public)")
        onRouteChanged?(reason)
    }
}
