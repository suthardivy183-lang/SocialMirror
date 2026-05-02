import AVFoundation
import Foundation
import Speech
import os

/// On-device speech recognition for `SpeechSegment`s. Strictly enforces
/// `requiresOnDeviceRecognition = true` so audio never leaves the device.
nonisolated final class TranscriptionEngine: @unchecked Sendable {
    private static let log = Logger(subsystem: "com.divy.SocialMirror", category: "Transcription")

    private let recognizer: SFSpeechRecognizer?
    private let timeoutSeconds: TimeInterval

    init(locale: Locale = Locale(identifier: "en-US"), timeoutSeconds: TimeInterval = 10) {
        self.recognizer = SFSpeechRecognizer(locale: locale)
        self.timeoutSeconds = timeoutSeconds
    }

    /// Static permission helper. Caller should invoke before transcribe().
    static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in cont.resume(returning: status) }
        }
    }

    /// True if on-device recognition is available for the configured locale.
    var isAvailable: Bool {
        guard let r = recognizer else { return false }
        return r.isAvailable && r.supportsOnDeviceRecognition
    }

    // MARK: - Single segment

    func transcribe(_ segment: SpeechSegment) async throws -> String {
        guard let recognizer, recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            throw TranscriptionError.notAvailable
        }

        let buffer = try makeBuffer(from: segment.samples)
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.append(buffer)
        request.endAudio()

        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { try await self.recognize(request: request, with: recognizer) }
            group.addTask { [timeoutSeconds] in
                try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                throw TranscriptionError.timedOut
            }
            let result = try await group.next() ?? ""
            group.cancelAll()
            return result
        }
    }

    // MARK: - Batch (concurrent, capped)

    func transcribeAll(_ segments: [DiarizedSegment]) async -> [TranscriptLine] {
        guard isAvailable else {
            Self.log.warning("On-device recognition unavailable; transcripts will be empty.")
            return []
        }

        let maxConcurrent = 4
        return await withTaskGroup(of: TranscriptLine?.self) { group in
            var inFlight = 0
            var iterator = segments.enumerated().makeIterator()
            var results: [TranscriptLine] = []

            // Prime up to maxConcurrent jobs.
            while inFlight < maxConcurrent, let (_, seg) = iterator.next() {
                inFlight += 1
                group.addTask { await self.makeLine(for: seg) }
            }

            // Drain and refill.
            while let line = await group.next() {
                inFlight -= 1
                if let line { results.append(line) }
                if let (_, seg) = iterator.next() {
                    inFlight += 1
                    group.addTask { await self.makeLine(for: seg) }
                }
            }
            return results.sorted { $0.timestampSeconds < $1.timestampSeconds }
        }
    }

    private func makeLine(for diarized: DiarizedSegment) async -> TranscriptLine? {
        do {
            let text = try await transcribe(diarized.speechSegment)
            guard !text.isEmpty else { return nil }
            return TranscriptLine(
                speakerIndex: diarized.speakerID,
                timestampSeconds: diarized.speechSegment.startTime,
                text: text
            )
        } catch {
            Self.log.warning("Transcription failed for segment: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Internals

    private func recognize(
        request: SFSpeechAudioBufferRecognitionRequest,
        with recognizer: SFSpeechRecognizer
    ) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            var resumed = false
            recognizer.recognitionTask(with: request) { result, error in
                if resumed { return }
                if let error {
                    resumed = true
                    cont.resume(throwing: TranscriptionError.recognitionFailed(error.localizedDescription))
                    return
                }
                if let result, result.isFinal {
                    resumed = true
                    cont.resume(returning: result.bestTranscription.formattedString)
                }
            }
        }
    }

    private func makeBuffer(from samples: [Float]) throws -> AVAudioPCMBuffer {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: AudioCaptureEngine.targetSampleRate,
            channels: 1,
            interleaved: false
        ) else { throw TranscriptionError.bufferFailed }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
            throw TranscriptionError.bufferFailed
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        guard let dst = buffer.floatChannelData?[0] else { throw TranscriptionError.bufferFailed }
        samples.withUnsafeBufferPointer { src in
            guard let s = src.baseAddress else { return }
            dst.update(from: s, count: samples.count)
        }
        return buffer
    }
}

enum TranscriptionError: Error, CustomStringConvertible {
    case notAvailable
    case bufferFailed
    case recognitionFailed(String)
    case timedOut

    var description: String {
        switch self {
        case .notAvailable: "On-device speech recognition is unavailable."
        case .bufferFailed: "Could not create audio buffer."
        case .recognitionFailed(let detail): "Recognition failed: \(detail)"
        case .timedOut: "Transcription timed out."
        }
    }
}

/// Spec-compatible alias.
typealias SessionRecordingViewModel = LiveSessionStore
