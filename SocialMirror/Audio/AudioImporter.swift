import AVFoundation
import Combine
import Foundation
import UniformTypeIdentifiers

/// Loads any AVFoundation-readable audio file and resamples it to the same
/// 16 kHz mono Float32 format the live pipeline produces, so all downstream
/// processing (VAD, embeddings, clustering, transcription, analysis) is
/// identical regardless of source.
@MainActor
final class AudioImporter: ObservableObject {
    @Published var isImporting = false
    @Published var importError: String?

    /// File-picker filter list. `UTType` initializers that fail (older runtimes,
    /// unknown extensions) collapse to `.audio` so the picker stays usable.
    nonisolated static let supportedTypes: [UTType] = {
        var types: [UTType] = [.audio, .mp3, .wav]
        for ext in ["m4a", "aac", "ogg", "opus"] {
            types.append(UTType(filenameExtension: ext) ?? .audio)
        }
        return types
    }()

    /// Decode + resample. Returns the raw 16 kHz mono Float32 samples plus
    /// the duration of the produced audio.
    nonisolated func loadAudioFile(url: URL) async throws -> (samples: [Float], duration: TimeInterval, originalURL: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let file = try AVAudioFile(forReading: url)
        let originalFormat = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)

        guard let originalBuffer = AVAudioPCMBuffer(pcmFormat: originalFormat, frameCapacity: frameCount) else {
            throw ImportError.bufferCreationFailed
        }
        try file.read(into: originalBuffer)

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: AudioCaptureEngine.targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw ImportError.conversionFailed
        }

        guard let converter = AVAudioConverter(from: originalFormat, to: targetFormat) else {
            throw ImportError.conversionFailed
        }

        let ratio = targetFormat.sampleRate / originalFormat.sampleRate
        // Pad by 64 frames so the converter's edge handling has room.
        let targetFrameCount = AVAudioFrameCount(Double(frameCount) * ratio + 64)
        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: targetFrameCount) else {
            throw ImportError.bufferCreationFailed
        }

        // Class wrapper so the closure can mutate state without falling
        // foul of Swift 6 strict-concurrency capture checks.
        final class FeedState { var consumed = false }
        let feed = FeedState()
        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, status in
            if feed.consumed {
                status.pointee = .endOfStream
                return nil
            }
            feed.consumed = true
            status.pointee = .haveData
            return originalBuffer
        }

        let result = converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)
        if let error { throw error }
        guard result != .error, let channelData = convertedBuffer.floatChannelData else {
            throw ImportError.extractionFailed
        }

        let sampleCount = Int(convertedBuffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: sampleCount))
        let duration = Double(sampleCount) / AudioCaptureEngine.targetSampleRate

        return (samples, duration, url)
    }

    /// Best-effort wall-clock duration probe without actually decoding.
    /// Used to show "~N minutes to analyze" in the import UI.
    nonisolated static func probeDuration(url: URL) -> TimeInterval? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        return Double(file.length) / file.processingFormat.sampleRate
    }
}

enum ImportError: LocalizedError {
    case bufferCreationFailed
    case conversionFailed
    case extractionFailed
    case unsupportedFormat
    case fileTooLarge

    var errorDescription: String? {
        switch self {
        case .bufferCreationFailed: "Could not read audio file."
        case .conversionFailed: "Could not convert audio format."
        case .extractionFailed: "Could not extract audio data."
        case .unsupportedFormat: "This audio format is not supported."
        case .fileTooLarge: "File is too large. Maximum 3 hours."
        }
    }
}
