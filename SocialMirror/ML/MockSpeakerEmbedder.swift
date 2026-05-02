import Foundation

/// Deterministic stand-in for the real ECAPA model. Maps each segment to one
/// of `speakerCount` "speakers", returning a normalized 192-dim vector that's
/// stable per-speaker (with tiny per-segment jitter so EMA centroid updates
/// behave realistically).
nonisolated final class MockSpeakerEmbedder: SpeakerEmbeddingProvider, @unchecked Sendable {
    static let embeddingDim = 192

    let speakerCount: Int
    private let bases: [[Float]] // one normalized base vector per speaker

    init(speakerCount: Int = 2) {
        precondition(speakerCount > 0, "speakerCount must be > 0")
        self.speakerCount = speakerCount
        self.bases = (0 ..< speakerCount).map { speaker in
            Self.makeBase(forSpeaker: speaker).normalized()
        }
    }

    func embed(_ segment: SpeechSegment) async throws -> SpeakerEmbedding {
        let speaker = Self.speakerIndex(for: segment, mod: speakerCount)
        let base = bases[speaker]
        let jitter = Self.jitter(for: segment, dim: Self.embeddingDim)
        var combined = [Float](repeating: 0, count: Self.embeddingDim)
        for i in 0 ..< Self.embeddingDim {
            combined[i] = base[i] + 0.05 * jitter[i] // 5% noise — too small to confuse clustering
        }
        return combined.normalized()
    }

    // MARK: - Deterministic helpers (pure functions, easy to reason about in tests)

    private static func speakerIndex(for segment: SpeechSegment, mod: Int) -> Int {
        // Hash the UUID's least-significant bytes to a stable bucket.
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in withUnsafeBytes(of: segment.id.uuid, Array.init) {
            hash = (hash ^ UInt64(byte)) &* 0x100000001b3
        }
        return Int(hash % UInt64(mod))
    }

    private static func makeBase(forSpeaker s: Int) -> [Float] {
        var vec = [Float](repeating: 0, count: embeddingDim)
        var rng = SeedableRNG(seed: UInt64(s) &* 0xdeadbeef &+ 0x1337)
        for i in 0 ..< embeddingDim {
            vec[i] = Float(rng.nextUnit() * 2 - 1)
        }
        return vec
    }

    private static func jitter(for segment: SpeechSegment, dim: Int) -> [Float] {
        var seed: UInt64 = 0
        for byte in withUnsafeBytes(of: segment.id.uuid, Array.init) {
            seed = (seed &* 31) &+ UInt64(byte)
        }
        var rng = SeedableRNG(seed: seed)
        return (0 ..< dim).map { _ in Float(rng.nextUnit() * 2 - 1) }
    }
}

/// Tiny linear-congruential RNG. Deterministic and self-contained; we never
/// want test results to depend on `SystemRandomNumberGenerator`.
nonisolated private struct SeedableRNG: Sendable {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed == 0 ? 0xdeadbeef : seed }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
    mutating func nextUnit() -> Double {
        Double(next() >> 11) / Double(UInt64(1) << 53)
    }
}
