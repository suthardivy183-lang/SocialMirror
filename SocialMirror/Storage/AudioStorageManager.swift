import AVFoundation
import CoreMedia
import Foundation

nonisolated final class AudioStorageManager: @unchecked Sendable {
    static let shared = AudioStorageManager()
    private init() {}

    // MARK: - User Preference
    var saveAudioEnabled: Bool {
        get {
            UserDefaults.standard.object(forKey: UserDefaultsKey.saveAudioEnabled) as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: UserDefaultsKey.saveAudioEnabled)
        }
    }

    var autoDeleteAudioDays: Int {
        get {
            UserDefaults.standard.integer(forKey: UserDefaultsKey.autoDeleteAudioDays)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: UserDefaultsKey.autoDeleteAudioDays)
        }
    }

    // MARK: - File Paths
    private var audioDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("audio")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func audioFileURL(for sessionID: UUID) -> URL {
        audioDirectory.appendingPathComponent("\(sessionID).m4a")
    }

    // MARK: - Save
    /// Call ONLY if `saveAudioEnabled == true`. Call right after recording stops, before analysis.
    func save(
        samples: [Float],
        sampleRate: Double = 16000,
        sessionID: UUID
    ) async throws -> URL {
        let outputURL = audioFileURL(for: sessionID)

        try? FileManager.default.removeItem(at: outputURL)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32000, // 32 kbps — speech quality
        ]

        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: outputSettings)
        writerInput.expectsMediaDataInRealTime = false
        writer.add(writerInput)

        let chunkSize = 4096
        var offset = 0
        var presentationTime = CMTime.zero

        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        while offset < samples.count {
            let end = min(offset + chunkSize, samples.count)
            let chunk = Array(samples[offset ..< end])

            if let buffer = makeSampleBuffer(
                from: chunk,
                sampleRate: sampleRate,
                presentationTime: presentationTime
            ) {
                while !writerInput.isReadyForMoreMediaData {
                    try await Task.sleep(nanoseconds: 10_000_000)
                }
                writerInput.append(buffer)
            }

            let duration = Double(chunk.count) / sampleRate
            presentationTime = CMTimeAdd(
                presentationTime,
                CMTimeMakeWithSeconds(duration, preferredTimescale: 44100)
            )
            offset = end
        }

        writerInput.markAsFinished()
        await writer.finishWriting()

        guard writer.status == .completed else {
            throw AudioStorageError.writeFailed
        }

        // Encrypt file at rest using iOS Data Protection
        try (outputURL as NSURL).setResourceValue(
            URLFileProtection.completeUnlessOpen,
            forKey: .fileProtectionKey
        )

        return outputURL
    }

    // MARK: - Delete
    func delete(sessionID: UUID) throws {
        let url = audioFileURL(for: sessionID)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    func deleteAll() {
        let files = (try? FileManager.default.contentsOfDirectory(at: audioDirectory, includingPropertiesForKeys: nil)) ?? []
        files.forEach { try? FileManager.default.removeItem(at: $0) }
    }

    // MARK: - Queries
    func exists(sessionID: UUID) -> Bool {
        FileManager.default.fileExists(atPath: audioFileURL(for: sessionID).path)
    }

    func fileSizeMB(sessionID: UUID) -> Double? {
        let url = audioFileURL(for: sessionID)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int
        else { return nil }
        return Double(size) / 1_048_576
    }

    func totalStorageUsedMB() -> Double {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: audioDirectory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: []
        )) ?? []
        return files.reduce(0.0) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            return total + Double(size) / 1_048_576
        }
    }

    func availableStorageMB() -> Double? {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
              let free = attrs[.systemFreeSize] as? Int
        else { return nil }
        return Double(free) / 1_048_576
    }

    // MARK: - Auto Delete
    /// Call this on every app launch from `@main`.
    func runAutoDelete() {
        let days = autoDeleteAudioDays
        guard days > 0 else { return }
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else { return }

        let files = (try? FileManager.default.contentsOfDirectory(
            at: audioDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: []
        )) ?? []

        for url in files {
            let created = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date()
            if created < cutoff {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    // MARK: - Private Helpers
    private func makeSampleBuffer(
        from samples: [Float],
        sampleRate: Double,
        presentationTime: CMTime
    ) -> CMSampleBuffer? {
        var format: CMFormatDescription?
        var asbd = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2,
            mFramesPerPacket: 1,
            mBytesPerFrame: 2,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 16,
            mReserved: 0
        )

        CMAudioFormatDescriptionCreate(
            allocator: nil,
            asbd: &asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &format
        )

        guard let fmt = format else { return nil }

        let int16Samples = samples.map {
            Int16(max(-32768, min(32767, $0 * 32767)))
        }

        var blockBuffer: CMBlockBuffer?
        let byteCount = int16Samples.count * 2

        CMBlockBufferCreateWithMemoryBlock(
            allocator: nil,
            memoryBlock: nil,
            blockLength: byteCount,
            blockAllocator: nil,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: byteCount,
            flags: 0,
            blockBufferOut: &blockBuffer
        )

        guard let blk = blockBuffer else { return nil }

        int16Samples.withUnsafeBytes { ptr in
            _ = CMBlockBufferReplaceDataBytes(
                with: ptr.baseAddress!,
                blockBuffer: blk,
                offsetIntoDestination: 0,
                dataLength: byteCount
            )
        }

        var sampleBuffer: CMSampleBuffer?
        var timing = CMSampleTimingInfo(
            duration: CMTimeMake(value: Int64(samples.count), timescale: Int32(sampleRate)),
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )

        CMSampleBufferCreate(
            allocator: nil,
            dataBuffer: blk,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: fmt,
            sampleCount: samples.count,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )

        return sampleBuffer
    }
}

// MARK: - Errors
enum AudioStorageError: Error {
    case writeFailed
    case fileNotFound
}
