import Accelerate
import AVFoundation
import Combine
import Foundation
import os

/// Captures microphone audio via `AVAudioEngine`, resamples to 16 kHz mono Float32,
/// and emits 20 ms frames (320 samples) plus an RMS level for waveform UI.
///
final class AudioCaptureEngine: ObservableObject {
    private static let log = Logger(subsystem: "com.divy.SocialMirror", category: "Capture")

    // MARK: - Constants
    nonisolated static let targetSampleRate: Double = 16_000
    nonisolated static let frameSize: Int = 320 // 20 ms at 16 kHz

    // MARK: - Published state (UI)
    @Published var isRecording: Bool = false
    @Published var currentLevel: Float = 0

    // MARK: - Callbacks (audio thread)
    /// Called for every 20 ms frame of resampled mono Float32 audio.
    nonisolated(unsafe) var onAudioFrame: (([Float]) -> Void)?
    /// Called with RMS for the same frame (also pushed into `currentLevel`).
    nonisolated(unsafe) var onLevelUpdate: ((Float) -> Void)?

    // MARK: - Private
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    private var leftover: [Float] = []
    private let processingQueue = DispatchQueue(label: "com.divy.SocialMirror.audioProcessing", qos: .userInitiated)

    init() {}

    // MARK: - Lifecycle

    func start() throws {
        guard !engine.isRunning else { return }

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)

        guard let target = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioCaptureError.formatUnavailable
        }
        targetFormat = target

        if inputFormat.sampleRate != Self.targetSampleRate || inputFormat.channelCount != 1 {
            converter = AVAudioConverter(from: inputFormat, to: target)
            if converter == nil { throw AudioCaptureError.converterUnavailable }
        } else {
            converter = nil
        }

        leftover.removeAll(keepingCapacity: true)

        // Tap is installed at the native input format; we resample inside the callback.
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.handleTap(buffer: buffer, inputFormat: inputFormat)
        }

        engine.prepare()
        try engine.start()

        Task { @MainActor in self.isRecording = true }
        Self.log.info("AudioCaptureEngine started (input rate=\(inputFormat.sampleRate, privacy: .public), channels=\(inputFormat.channelCount, privacy: .public))")
    }

    func stop() {
        guard engine.isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        Task { @MainActor in
            self.isRecording = false
            self.currentLevel = 0
        }
        Self.log.info("AudioCaptureEngine stopped")
    }

    /// Reset the engine after a route change. Caller should `stop()` then `start()`.
    func reset() {
        engine.reset()
        leftover.removeAll(keepingCapacity: true)
    }

    // MARK: - Tap processing

    private func handleTap(buffer: AVAudioPCMBuffer, inputFormat: AVAudioFormat) {
        let resampled: [Float]
        if let converter, let targetFormat {
            resampled = convert(buffer: buffer, using: converter, target: targetFormat) ?? []
        } else {
            resampled = floats(from: buffer)
        }
        guard !resampled.isEmpty else { return }
        emitFrames(from: resampled)
    }

    private func convert(
        buffer: AVAudioPCMBuffer,
        using converter: AVAudioConverter,
        target: AVAudioFormat
    ) -> [Float]? {
        // Output frame capacity proportional to sample-rate ratio, with a bit of slack.
        let ratio = target.sampleRate / buffer.format.sampleRate
        let outFrames = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 64)
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: outFrames) else {
            return nil
        }

        var consumed = false
        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, status in
            if consumed {
                status.pointee = .endOfStream
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        let result = converter.convert(to: outBuffer, error: &error, withInputFrom: inputBlock)

        if let error {
            Self.log.error("AVAudioConverter error: \(error, privacy: .public)")
        }
        guard result != .error, let data = outBuffer.floatChannelData?[0] else { return nil }
        let count = Int(outBuffer.frameLength)
        return Array(UnsafeBufferPointer(start: data, count: count))
    }

    private func floats(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let data = buffer.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: data, count: Int(buffer.frameLength)))
    }

    /// Accumulate leftover + new samples and slice into 320-sample frames.
    private func emitFrames(from samples: [Float]) {
        leftover.append(contentsOf: samples)
        while leftover.count >= Self.frameSize {
            let frame = Array(leftover.prefix(Self.frameSize))
            leftover.removeFirst(Self.frameSize)
            let rms = Self.rms(frame)
            onAudioFrame?(frame)
            onLevelUpdate?(rms)
            Task { @MainActor in self.currentLevel = rms }
        }
    }

    // MARK: - DSP

    /// RMS energy via Accelerate (`vDSP_rmsqv`).
    nonisolated static func rms(_ samples: [Float]) -> Float {
        var result: Float = 0
        samples.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return }
            vDSP_rmsqv(base, 1, &result, vDSP_Length(samples.count))
        }
        return result
    }
}

// MARK: - Errors
enum AudioCaptureError: Error {
    case formatUnavailable
    case converterUnavailable
}
