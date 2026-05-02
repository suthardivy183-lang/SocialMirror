import Foundation
import Testing
@testable import SocialMirror

struct OnlineSpeakerClustererTests {
    private static let dim = 192

    /// Build a normalized embedding from a single seed value. Different seeds
    /// produce vectors with controlled cosine similarity (small seed diff =
    /// near-1 similarity; large diff = near-0 or negative).
    private static func embedding(seed: Float) -> SpeakerEmbedding {
        (0 ..< dim).map { i in
            sin(Float(i) * 0.137 + seed) + 0.3 * cos(Float(i) * 0.41 + seed * 1.7)
        }.normalized()
    }

    /// Two highly orthogonal vectors used as clearly-distinct "speakers".
    private static func basisA() -> SpeakerEmbedding {
        var v = [Float](repeating: 0, count: dim)
        for i in 0 ..< dim where i.isMultiple(of: 2) { v[i] = 1 }
        return v.normalized()
    }

    private static func basisB() -> SpeakerEmbedding {
        var v = [Float](repeating: 0, count: dim)
        for i in 0 ..< dim where !i.isMultiple(of: 2) { v[i] = 1 }
        return v.normalized()
    }

    @Test func twoDistinctEmbeddingsGetDifferentIDs() {
        let clusterer = OnlineSpeakerClusterer()
        let a = Self.basisA()
        let b = Self.basisB()
        // basisA and basisB share zero non-zero indices ⇒ cosine similarity = 0
        #expect(a.cosineSimilarity(to: b) < 0.5)

        let id1 = clusterer.assign(embedding: a, at: 0, duration: 1)
        let id2 = clusterer.assign(embedding: b, at: 1, duration: 1)
        #expect(id1 != id2)
        #expect(clusterer.clusters.count == 2)
    }

    @Test func sameEmbeddingTwiceGetsSameID() {
        let clusterer = OnlineSpeakerClusterer()
        let a = Self.embedding(seed: 1.0)
        let id1 = clusterer.assign(embedding: a, at: 0, duration: 1)
        let id2 = clusterer.assign(embedding: a, at: 1, duration: 1)
        #expect(id1 == id2)
        #expect(clusterer.clusters.count == 1)
        #expect(clusterer.clusters[0].sampleCount == 2)
    }

    @Test func similarityAtThresholdAssignsToExistingCluster() {
        // We construct two vectors whose cosine similarity is exactly equal to
        // the threshold (0.75) by mixing two orthogonal basis vectors.
        let threshold: Float = 0.75
        let clusterer = OnlineSpeakerClusterer(similarityThreshold: threshold)

        let a = Self.basisA()
        let b = Self.basisB()
        // mix = α·a + sqrt(1-α²)·b → cosine(a, mix) = α
        let alpha: Float = threshold
        let beta = sqrt(1 - alpha * alpha)
        var mix = [Float](repeating: 0, count: Self.dim)
        for i in 0 ..< Self.dim {
            mix[i] = alpha * a[i] + beta * b[i]
        }
        mix = mix.normalized()
        let sim = a.cosineSimilarity(to: mix)
        #expect(abs(sim - threshold) < 0.01) // numerically very close

        let id1 = clusterer.assign(embedding: a, at: 0, duration: 1)
        let id2 = clusterer.assign(embedding: mix, at: 1, duration: 1)
        #expect(id1 == id2) // at-threshold should snap to existing cluster
        #expect(clusterer.clusters.count == 1)
    }

    /// Sparse non-overlapping one-hot region — guaranteed orthogonal between speakers,
    /// guaranteed near-identical when two share the same region with a small shift.
    private static func sparse(speaker: Int, shift: Int = 0) -> SpeakerEmbedding {
        var v = [Float](repeating: 0, count: dim)
        let regionStart = (speaker * 32 + shift) % dim
        for i in 0 ..< 30 {
            v[(regionStart + i) % dim] = 1
        }
        return v.normalized()
    }

    @Test func capRespectedAndSeventhEmbeddingGoesToClosest() {
        let clusterer = OnlineSpeakerClusterer(maxSpeakers: 6)
        var ids: [Int] = []
        // 6 mutually orthogonal embeddings — each occupies a distinct 30-index window.
        for s in 0 ..< 6 {
            let e = Self.sparse(speaker: s)
            ids.append(clusterer.assign(embedding: e, at: TimeInterval(s), duration: 1))
        }
        #expect(Set(ids).count == 6)
        #expect(clusterer.clusters.count == 6)

        // 7th is in speaker-2's region, shifted by 1 → 29/30 indices overlap → very high similarity.
        let seventh = Self.sparse(speaker: 2, shift: 1)
        let id7 = clusterer.assign(embedding: seventh, at: 100, duration: 1)
        #expect(clusterer.clusters.count == 6) // cap respected
        #expect(id7 == ids[2])                 // routed to closest existing speaker
    }

    @Test func resetClearsState() {
        let clusterer = OnlineSpeakerClusterer()
        _ = clusterer.assign(embedding: Self.basisA(), at: 0, duration: 1)
        _ = clusterer.assign(embedding: Self.basisB(), at: 1, duration: 1)
        #expect(clusterer.clusters.count == 2)
        clusterer.reset()
        #expect(clusterer.clusters.count == 0)
    }
}

struct SpeakerEmbeddingMathTests {
    @Test func cosineOfIdenticalVectorsIsOne() {
        let v: [Float] = (0 ..< 192).map { Float($0) + 1 }
        #expect(abs(v.cosineSimilarity(to: v) - 1.0) < 1e-5)
    }

    @Test func cosineOfOrthogonalVectorsIsZero() {
        var a = [Float](repeating: 0, count: 192)
        var b = [Float](repeating: 0, count: 192)
        for i in 0 ..< 192 {
            if i.isMultiple(of: 2) { a[i] = 1 } else { b[i] = 1 }
        }
        #expect(abs(a.cosineSimilarity(to: b)) < 1e-5)
    }

    @Test func normalizedHasUnitNorm() {
        let v: [Float] = (1 ... 192).map { Float($0) }
        let n = v.normalized()
        let normSq = n.reduce(0) { $0 + $1 * $1 }
        #expect(abs(normSq - 1.0) < 1e-4)
    }
}
