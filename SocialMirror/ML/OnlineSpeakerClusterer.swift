import Foundation

/// Single cluster representing one speaker discovered in the session.
struct SpeakerCluster: Sendable {
    var centroid: SpeakerEmbedding
    var sampleCount: Int
    var speakerID: Int
    var firstSeenAt: TimeInterval
    var totalTalkTime: TimeInterval
}

/// Online (streaming) speaker clusterer. Each new embedding is matched to
/// the closest existing cluster by cosine similarity; if nothing exceeds the
/// threshold and we still have head-room, a new cluster is created.
///
/// After the session ends, `postSessionRefinement()` re-clusters all stored
/// embeddings agglomeratively to fix online-mode drift.
nonisolated final class OnlineSpeakerClusterer: @unchecked Sendable {
    let similarityThreshold: Float
    let maxSpeakers: Int

    private(set) var clusters: [SpeakerCluster] = []
    private var history: [(speakerID: Int, embedding: SpeakerEmbedding)] = []
    private static let emaAlpha: Float = 0.1

    init(similarityThreshold: Float = 0.75, maxSpeakers: Int = 6) {
        self.similarityThreshold = similarityThreshold
        self.maxSpeakers = maxSpeakers
    }

    // MARK: - Streaming assignment

    @discardableResult
    func assign(embedding: SpeakerEmbedding, at timestamp: TimeInterval, duration: TimeInterval) -> Int {
        // 1. First-ever embedding starts cluster 0.
        guard !clusters.isEmpty else {
            let cluster = SpeakerCluster(
                centroid: embedding,
                sampleCount: 1,
                speakerID: 0,
                firstSeenAt: timestamp,
                totalTalkTime: duration
            )
            clusters.append(cluster)
            history.append((0, embedding))
            return 0
        }

        // 2. Find best-matching cluster.
        var bestIndex = 0
        var bestSimilarity: Float = -.infinity
        for (idx, cluster) in clusters.enumerated() {
            let sim = cluster.centroid.cosineSimilarity(to: embedding)
            if sim > bestSimilarity {
                bestSimilarity = sim
                bestIndex = idx
            }
        }

        // 3. Above threshold → assign + EMA update.
        if bestSimilarity >= similarityThreshold {
            update(clusterIndex: bestIndex, with: embedding, duration: duration)
            history.append((clusters[bestIndex].speakerID, embedding))
            return clusters[bestIndex].speakerID
        }

        // 4. Below threshold but room for a new speaker → spawn one.
        if clusters.count < maxSpeakers {
            let newID = clusters.count
            let cluster = SpeakerCluster(
                centroid: embedding,
                sampleCount: 1,
                speakerID: newID,
                firstSeenAt: timestamp,
                totalTalkTime: duration
            )
            clusters.append(cluster)
            history.append((newID, embedding))
            return newID
        }

        // 5. Cap reached → assign to closest match anyway.
        update(clusterIndex: bestIndex, with: embedding, duration: duration)
        history.append((clusters[bestIndex].speakerID, embedding))
        return clusters[bestIndex].speakerID
    }

    private func update(clusterIndex: Int, with embedding: SpeakerEmbedding, duration: TimeInterval) {
        let alpha = Self.emaAlpha
        let oldCentroid = clusters[clusterIndex].centroid
        var newCentroid = [Float](repeating: 0, count: oldCentroid.count)
        for i in 0 ..< oldCentroid.count {
            newCentroid[i] = alpha * embedding[i] + (1 - alpha) * oldCentroid[i]
        }
        clusters[clusterIndex].centroid = newCentroid.normalized()
        clusters[clusterIndex].sampleCount += 1
        clusters[clusterIndex].totalTalkTime += duration
    }

    // MARK: - Post-session refinement

    /// Re-runs agglomerative clustering on the full embedding history to fix
    /// drift from the streaming pass. Returns a mapping `oldSpeakerID → refinedSpeakerID`.
    /// If two online clusters were really one speaker, both old IDs now map to the same new ID.
    func postSessionRefinement() -> [Int: Int] {
        guard !history.isEmpty else { return [:] }

        // Start each historical embedding in its own cluster (use a fresh ID space).
        var refined: [[SpeakerEmbedding]] = history.map { [$0.embedding] }

        // Greedy agglomerative merge: merge the closest pair while they exceed the threshold.
        while refined.count > 1 {
            var bestI = 0
            var bestJ = 1
            var bestSim: Float = -.infinity
            for i in 0 ..< refined.count {
                for j in (i + 1) ..< refined.count {
                    let cI = centroid(of: refined[i])
                    let cJ = centroid(of: refined[j])
                    let sim = cI.cosineSimilarity(to: cJ)
                    if sim > bestSim {
                        bestSim = sim
                        bestI = i
                        bestJ = j
                    }
                }
            }
            if bestSim < similarityThreshold { break }
            refined[bestI].append(contentsOf: refined[bestJ])
            refined.remove(at: bestJ)
        }

        // Cap to maxSpeakers by merging the smallest into the closest survivor.
        while refined.count > maxSpeakers {
            let smallestIdx = refined.indices.min(by: { refined[$0].count < refined[$1].count }) ?? 0
            let smallCentroid = centroid(of: refined[smallestIdx])
            let targetIdx = refined.indices
                .filter { $0 != smallestIdx }
                .max(by: { i, j in
                    centroid(of: refined[i]).cosineSimilarity(to: smallCentroid)
                        < centroid(of: refined[j]).cosineSimilarity(to: smallCentroid)
                }) ?? 0
            refined[targetIdx].append(contentsOf: refined[smallestIdx])
            refined.remove(at: smallestIdx)
        }

        // Walk history once more to map old → new.
        var mapping: [Int: Int] = [:]
        for (sample, entry) in history.enumerated() {
            let assigned = refined.firstIndex(where: { group in
                group.contains(where: { $0 == history[sample].embedding })
            }) ?? 0
            mapping[entry.speakerID] = assigned
        }
        return mapping
    }

    private func centroid(of group: [SpeakerEmbedding]) -> SpeakerEmbedding {
        guard let first = group.first else { return [] }
        var sum = [Float](repeating: 0, count: first.count)
        for emb in group {
            for i in 0 ..< first.count { sum[i] += emb[i] }
        }
        let n = Float(group.count)
        for i in 0 ..< first.count { sum[i] /= n }
        return sum.normalized()
    }

    // MARK: - Reset

    func reset() {
        clusters.removeAll(keepingCapacity: true)
        history.removeAll(keepingCapacity: true)
    }
}
