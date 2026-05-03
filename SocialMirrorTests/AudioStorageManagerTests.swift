import Foundation
import Testing
@testable import SocialMirror

/// AudioStorageManager talks to the real filesystem (sandbox documents dir).
/// Serialized so `deleteAll()` doesn't trample sibling tests' files when
/// Swift Testing parallelizes across clones.
@Suite(.serialized)
struct AudioStorageManagerTests {
    private static let mgr = AudioStorageManager.shared

    /// 0.5 s of 16 kHz silence — enough for AVAssetWriter to produce a
    /// non-empty file but tiny enough to make the test fast.
    private static func silenceSamples() -> [Float] {
        Array(repeating: 0, count: 8_000)
    }

    @Test func saveThenExistsThenSize() async throws {
        let id = UUID()
        defer { try? Self.mgr.delete(sessionID: id) }

        #expect(Self.mgr.exists(sessionID: id) == false)
        let url = try await Self.mgr.save(samples: Self.silenceSamples(), sessionID: id)

        #expect(Self.mgr.exists(sessionID: id) == true)
        #expect(FileManager.default.fileExists(atPath: url.path))
        let mb = Self.mgr.fileSizeMB(sessionID: id)
        #expect(mb != nil)
        #expect((mb ?? 0) > 0)
    }

    @Test func deleteRemovesFile() async throws {
        let id = UUID()
        _ = try await Self.mgr.save(samples: Self.silenceSamples(), sessionID: id)
        #expect(Self.mgr.exists(sessionID: id) == true)
        try Self.mgr.delete(sessionID: id)
        #expect(Self.mgr.exists(sessionID: id) == false)
    }

    @Test func totalStorageReflectsSavedFiles() async throws {
        let id1 = UUID()
        let id2 = UUID()
        defer {
            try? Self.mgr.delete(sessionID: id1)
            try? Self.mgr.delete(sessionID: id2)
        }
        let before = Self.mgr.totalStorageUsedMB()
        _ = try await Self.mgr.save(samples: Self.silenceSamples(), sessionID: id1)
        _ = try await Self.mgr.save(samples: Self.silenceSamples(), sessionID: id2)
        let after = Self.mgr.totalStorageUsedMB()
        #expect(after > before)
    }

    @Test func availableStorageIsPositive() {
        let avail = Self.mgr.availableStorageMB()
        #expect(avail != nil)
        #expect((avail ?? 0) > 0)
    }

    @Test func autoDeleteRespectsZeroDays() async throws {
        // 0 days means "never auto-delete". Save a file, run autoDelete, file
        // must still exist regardless of when it was created.
        let id = UUID()
        defer { try? Self.mgr.delete(sessionID: id) }
        _ = try await Self.mgr.save(samples: Self.silenceSamples(), sessionID: id)

        let savedDays = Self.mgr.autoDeleteAudioDays
        Self.mgr.autoDeleteAudioDays = 0
        Self.mgr.runAutoDelete()
        defer { Self.mgr.autoDeleteAudioDays = savedDays }

        #expect(Self.mgr.exists(sessionID: id) == true)
    }

    @Test func deleteAllClearsEverything() async throws {
        let id = UUID()
        _ = try await Self.mgr.save(samples: Self.silenceSamples(), sessionID: id)
        #expect(Self.mgr.exists(sessionID: id) == true)
        Self.mgr.deleteAll()
        #expect(Self.mgr.exists(sessionID: id) == false)
        #expect(Self.mgr.totalStorageUsedMB() == 0)
    }
}
