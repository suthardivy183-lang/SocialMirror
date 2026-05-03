import Accelerate
import Foundation

/// Pure-function acoustic feature extractors. All inner loops use Accelerate
/// (`vDSP_*`) so they're vectorized and safe to call from any thread.
nonisolated enum AcousticFeatureExtractor {
    // MARK: - Pitch (normalized autocorrelation)

    /// Estimate fundamental frequency in Hz using *normalized* time-domain
    /// autocorrelation. Each lag is divided by the geometric mean of the
    /// energies of its two windows so smaller lags don't always win merely
    /// by summing more terms — this was the bug that pinned every estimate
    /// to the upper search bound. Returns 0 when no plausible voiced pitch.
    static func extractPitch(from samples: [Float], sampleRate: Float = 16_000) -> Float {
        let n = samples.count
        guard n >= 1024 else { return 0 } // ≥ ~64 ms to resolve 80 Hz

        // Voice fundamental range: 80–400 Hz → lag in samples.
        let minLag = max(2, Int(sampleRate / 400))   // 40 @ 16 kHz
        let maxLag = min(n - 1, Int(sampleRate / 80)) // 200 @ 16 kHz
        guard maxLag > minLag else { return 0 }

        var bestLag = minLag
        var bestNorm: Float = 0

        samples.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return }
            for lag in minLag ... maxLag {
                let span = vDSP_Length(n - lag)
                var corr: Float = 0
                var e1: Float = 0
                var e2: Float = 0
                vDSP_dotpr(base, 1, base.advanced(by: lag), 1, &corr, span)
                vDSP_svesq(base, 1, &e1, span)
                vDSP_svesq(base.advanced(by: lag), 1, &e2, span)
                let denom = sqrt(e1 * e2)
                let norm = denom > 0 ? corr / denom : 0
                if norm > bestNorm {
                    bestNorm = norm
                    bestLag = lag
                }
            }
        }

        // Voicing gate: a real periodic signal at fundamental F hits >0.5
        // normalized autocorrelation easily; sub-0.4 is almost certainly
        // unvoiced (whispers, fricatives, room noise).
        guard bestNorm > 0.4 else { return 0 }

        return sampleRate / Float(bestLag)
    }

    // MARK: - Energy

    /// RMS energy in dBFS. Floor at -90 dB to avoid -∞ on pure silence.
    static func extractEnergy(from samples: [Float]) -> Float {
        guard !samples.isEmpty else { return -90 }
        var rms: Float = 0
        samples.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return }
            vDSP_rmsqv(base, 1, &rms, vDSP_Length(samples.count))
        }
        guard rms > 0 else { return -90 }
        return 20 * log10(rms)
    }

    // MARK: - Speech rate

    static func extractSpeechRate(wordCount: Int, duration: TimeInterval) -> Float {
        guard duration > 0 else { return 0 }
        return Float(Double(wordCount) / (duration / 60.0))
    }

    // MARK: - Pitch variance

    /// Population variance of a pitch track. Pitches that are 0 (unvoiced
    /// frames) are excluded so they don't drag the variance down artificially.
    static func extractPitchVariance(pitches: [Float]) -> Float {
        let voiced = pitches.filter { $0 > 0 }
        guard voiced.count > 1 else { return 0 }
        var mean: Float = 0
        var stddev: Float = 0
        voiced.withUnsafeBufferPointer { src in
            guard let s = src.baseAddress else { return }
            // vDSP_normalize produces (in addition to a normalized output)
            // the input's mean and stddev — we ignore the output buffer.
            var sink = [Float](repeating: 0, count: voiced.count)
            sink.withUnsafeMutableBufferPointer { dst in
                guard let d = dst.baseAddress else { return }
                vDSP_normalize(s, 1, d, 1, &mean, &stddev, vDSP_Length(voiced.count))
            }
        }
        return stddev * stddev
    }
}
