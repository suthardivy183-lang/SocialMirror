import Foundation
import Testing
@testable import SocialMirror

struct CoreMLSpeakerEmbedderTests {
    /// Skip-aware: returns nil if `ECAPA.mlpackage`/`.mlmodelc` is absent.
    /// Tests in CI without the model don't fail; they no-op.
    private static func tryMakeEmbedder() -> CoreMLSpeakerEmbedder? {
        try? CoreMLSpeakerEmbedder()
    }

    @Test func threeSecondsOfSilenceProduces192DimEmbedding() async throws {
        guard let embedder = Self.tryMakeEmbedder() else {
            Issue.record("ECAPA model not bundled in test host — skipping")
            return
        }

        // 3 s of pure silence at 16 kHz = 48 000 samples.
        let segment = SpeechSegment(
            samples: Array(repeating: 0, count: 48_000),
            startTime: 0,
            endTime: 3,
            durationSeconds: 3
        )

        let embedding = try await embedder.embed(segment)
        #expect(embedding.count == 192)
        // Floats can't all be NaN/inf for any sane model output.
        #expect(embedding.allSatisfy { $0.isFinite })
    }

    @Test func oneSecondOfNoiseProduces192DimEmbedding() async throws {
        guard let embedder = Self.tryMakeEmbedder() else {
            Issue.record("ECAPA model not bundled in test host — skipping")
            return
        }

        // 1 s of light white noise (deterministic LCG so the test is reproducible).
        var state: UInt64 = 0x1234_5678_9abc_def0
        let samples: [Float] = (0 ..< 16_000).map { _ in
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return (Float(state >> 32) / Float(UInt32.max) - 0.5) * 0.05
        }
        let segment = SpeechSegment(
            samples: samples,
            startTime: 0,
            endTime: 1,
            durationSeconds: 1
        )

        let embedding = try await embedder.embed(segment)
        #expect(embedding.count == 192)
        #expect(embedding.allSatisfy { $0.isFinite })
    }
}
