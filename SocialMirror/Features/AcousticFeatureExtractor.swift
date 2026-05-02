import Accelerate
import Foundation

/// Pure-function acoustic feature extractors. All inner loops use Accelerate
/// (`vDSP_*`) so they're vectorized and safe to call from any thread.
nonisolated enum AcousticFeatureExtractor {
    // MARK: - Pitch (autocorrelation method)

    /// Estimate fundamental frequency in Hz using time-domain autocorrelation.
    /// Returns 0 when no plausible pitch is found (silence or noise).
    static func extractPitch(from samples: [Float], sampleRate: Float = 16_000) -> Float {
        let n = samples.count
        guard n >= 1024 else { return 0 } // need ≥ ~64 ms to resolve 80 Hz reliably

        // Voice fundamental range: 80–400 Hz → lag in samples
        let minLag = max(2, Int(sampleRate / 400))   // 40 @ 16 kHz
        let maxLag = min(n - 1, Int(sampleRate / 80)) // 200 @ 16 kHz
        guard maxLag > minLag else { return 0 }

        var bestLag = minLag
        var bestCorr: Float = -.infinity

        // Per-lag dot product (each call is SIMD-accelerated by vDSP).
        samples.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return }
            for lag in minLag ... maxLag {
                var corr: Float = 0
                vDSP_dotpr(base, 1, base.advanced(by: lag), 1, &corr, vDSP_Length(n - lag))
                if corr > bestCorr {
                    bestCorr = corr
                    bestLag = lag
                }
            }
        }

        // Reject weak peaks — likely noise rather than voiced speech.
        var totalEnergy: Float = 0
        samples.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return }
            vDSP_svesq(base, 1, &totalEnergy, vDSP_Length(n))
        }
        let normalizedPeak = bestCorr / max(totalEnergy, .leastNonzeroMagnitude)
        guard normalizedPeak > 0.3 else { return 0 }

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
