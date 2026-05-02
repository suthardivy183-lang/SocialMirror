import Accelerate
import Foundation

/// 192-dimensional speaker embedding vector (ECAPA-TDNN output).
typealias SpeakerEmbedding = [Float]

extension Array where Element == Float {
    /// Cosine similarity in [-1, 1] using Accelerate.
    /// `dot(a, b) / (‖a‖ · ‖b‖)`. Returns 0 if either vector has zero norm.
    nonisolated func cosineSimilarity(to other: [Float]) -> Float {
        precondition(count == other.count, "cosine similarity requires equal-length vectors")
        guard count > 0 else { return 0 }

        var dot: Float = 0
        var sqA: Float = 0
        var sqB: Float = 0
        let n = vDSP_Length(count)

        self.withUnsafeBufferPointer { aPtr in
            other.withUnsafeBufferPointer { bPtr in
                guard let a = aPtr.baseAddress, let b = bPtr.baseAddress else { return }
                vDSP_dotpr(a, 1, b, 1, &dot, n)
                vDSP_svesq(a, 1, &sqA, n)
                vDSP_svesq(b, 1, &sqB, n)
            }
        }

        let denom = sqrt(sqA) * sqrt(sqB)
        guard denom > 0 else { return 0 }
        return dot / denom
    }

    /// L2-normalize. Returns the original vector unchanged if norm is zero.
    nonisolated func normalized() -> [Float] {
        guard count > 0 else { return self }

        var sumSq: Float = 0
        let n = vDSP_Length(count)
        self.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return }
            vDSP_svesq(base, 1, &sumSq, n)
        }
        let norm = sqrt(sumSq)
        guard norm > 0 else { return self }

        var divisor = norm
        var result = [Float](repeating: 0, count: count)
        self.withUnsafeBufferPointer { src in
            result.withUnsafeMutableBufferPointer { dst in
                guard let s = src.baseAddress, let d = dst.baseAddress else { return }
                vDSP_vsdiv(s, 1, &divisor, d, 1, n)
            }
        }
        return result
    }
}
