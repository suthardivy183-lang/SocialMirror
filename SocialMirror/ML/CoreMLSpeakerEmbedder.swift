import Accelerate
import CoreML
import Foundation
import os
import os.signpost

/// Production speaker embedder backed by `ECAPA.mlpackage`.
///
/// Pipeline: 16 kHz Float32 PCM →
///   25 ms windows hopped 10 ms →
///   Hann-windowed, zero-padded, 512-pt real FFT →
///   power spectrum (257 bins) →
///   80-bin HTK mel filterbank (linear-power) →
///   natural log →
///   `MLMultiArray[1, nFrames, 80]` →
///   ECAPA inference →
///   `MLMultiArray[1, 1, 192]` → `[Float]` of 192 values.
///
/// Throws `EmbedderError.modelNotFound` if `ECAPA.mlpackage`/`.mlmodelc` is
/// not in the bundle. All Accelerate calls are vDSP — no naive loops in the
/// hot path (mel matrix multiply uses `vDSP_mmul`; log is computed via
/// `vvlogf` from vForce on the floored mel energies).
nonisolated final class CoreMLSpeakerEmbedder: SpeakerEmbeddingProvider, @unchecked Sendable {
    private static let log = Logger(subsystem: "com.divy.SocialMirror", category: "Embedder")
    private static let signposter = OSSignposter(subsystem: "com.divy.SocialMirror", category: "ECAPA")

    // MARK: - Constants (must match the values ECAPA.mlpackage was trained on)
    nonisolated static let sampleRate: Double = 16_000
    nonisolated static let nFFT = 512
    nonisolated static let log2N = vDSP_Length(9) // log2(512)
    nonisolated static let winLength = 400 // 25 ms @ 16 kHz
    nonisolated static let hopLength = 160 // 10 ms @ 16 kHz
    nonisolated static let nMels = 80
    nonisolated static let nBins = nFFT / 2 + 1 // 257
    nonisolated static let embeddingDim = 192
    nonisolated static let logFloor: Float = 1e-10

    /// Match the actual model bundled — see `metadata.json` inside `ECAPA.mlmodelc`.
    var inputFeatureName: String = "fbank_input"
    var outputFeatureName: String = "var_965"

    /// Model accepts shapeRange [1, 100…1000, 80]. Anything below 100 frames
    /// trips a Core ML shape assertion; pad short inputs to the minimum.
    nonisolated static let minFrames = 100
    nonisolated static let maxFrames = 1_000

    // MARK: - State (built once at init)
    private let model: MLModel
    private let fftSetup: FFTSetup
    private let hannWindow: [Float]
    private let melMatrix: [Float] // row-major [nMels × nBins]

    init(modelName: String = "ECAPA", configuration: MLModelConfiguration = .init()) throws {
        configuration.computeUnits = .all // CPU + GPU + ANE

        guard let url = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc")
            ?? Bundle.main.url(forResource: modelName, withExtension: "mlpackage")
        else {
            throw EmbedderError.modelNotFound
        }

        do {
            self.model = try MLModel(contentsOf: url, configuration: configuration)
        } catch {
            throw EmbedderError.inferenceFailed("MLModel init: \(error.localizedDescription)")
        }

        guard let setup = vDSP_create_fftsetup(Self.log2N, FFTRadix(kFFTRadix2)) else {
            throw EmbedderError.inferenceFailed("vDSP_create_fftsetup failed")
        }
        self.fftSetup = setup

        var window = [Float](repeating: 0, count: Self.winLength)
        vDSP_hann_window(&window, vDSP_Length(Self.winLength), Int32(vDSP_HANN_NORM))
        self.hannWindow = window

        self.melMatrix = Self.buildMelMatrix()

        Self.log.info("Loaded ECAPA model from \(url.lastPathComponent, privacy: .public)")
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    // MARK: - Public

    func embed(_ segment: SpeechSegment) async throws -> SpeakerEmbedding {
        let signpostID = Self.signposter.makeSignpostID()
        let signpostState = Self.signposter.beginInterval(
            "ECAPA inference",
            id: signpostID,
            "samples=\(segment.samples.count)"
        )
        defer { Self.signposter.endInterval("ECAPA inference", signpostState) }

        let start = CFAbsoluteTimeGetCurrent()

        let (features, nFrames) = computeMelFeatures(from: segment.samples)
        guard nFrames > 0 else { throw EmbedderError.invalidOutputShape }

        let input = try makeInputArray(features: features, nFrames: nFrames)

        let provider: MLFeatureProvider
        do {
            let dict: [String: MLFeatureValue] = [inputFeatureName: MLFeatureValue(multiArray: input)]
            provider = try MLDictionaryFeatureProvider(dictionary: dict)
        } catch {
            throw EmbedderError.inferenceFailed("input provider: \(error.localizedDescription)")
        }

        let output: MLFeatureProvider
        do {
            output = try await model.prediction(from: provider)
        } catch {
            throw EmbedderError.inferenceFailed("prediction: \(error.localizedDescription)")
        }

        guard let multi = output.featureValue(for: outputFeatureName)?.multiArrayValue else {
            throw EmbedderError.invalidOutputShape
        }

        let embedding = try unpackEmbedding(multi)
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
        Self.log.debug("ECAPA inference: \(elapsedMs, format: .fixed(precision: 2), privacy: .public) ms (\(nFrames, privacy: .public) frames)")
        return embedding
    }

    // MARK: - Mel feature extraction

    /// Returns mel features as a flat row-major array of `nFrames × nMels`
    /// floats plus the frame count.
    private func computeMelFeatures(from samples: [Float]) -> (features: [Float], nFrames: Int) {
        guard samples.count >= Self.winLength else { return ([], 0) }

        let nFrames = 1 + (samples.count - Self.winLength) / Self.hopLength
        var output = [Float](repeating: 0, count: nFrames * Self.nMels)

        // Per-frame scratch buffers (allocated once, reused).
        var windowed = [Float](repeating: 0, count: Self.winLength)
        var paddedFrame = [Float](repeating: 0, count: Self.nFFT)
        var realParts = [Float](repeating: 0, count: Self.nFFT / 2)
        var imagParts = [Float](repeating: 0, count: Self.nFFT / 2)
        var power = [Float](repeating: 0, count: Self.nBins)
        var melEnergies = [Float](repeating: 0, count: Self.nMels)

        for f in 0 ..< nFrames {
            let offset = f * Self.hopLength

            // Slice the input frame into `windowed`.
            samples.withUnsafeBufferPointer { sPtr in
                guard let s = sPtr.baseAddress else { return }
                windowed.withUnsafeMutableBufferPointer { wPtr in
                    guard let w = wPtr.baseAddress else { return }
                    w.update(from: s.advanced(by: offset), count: Self.winLength)
                }
            }

            // Apply Hann window (in-place).
            vDSP_vmul(windowed, 1, hannWindow, 1, &windowed, 1, vDSP_Length(Self.winLength))

            // Zero-pad the windowed frame up to nFFT.
            paddedFrame.withUnsafeMutableBufferPointer { pPtr in
                guard let p = pPtr.baseAddress else { return }
                p.update(repeating: 0, count: Self.nFFT)
                p.update(from: windowed, count: Self.winLength)
            }

            // Real-to-complex FFT in split format. Pack interleaved data into
            // split (DC, k1_re, k1_im, k2_re, k2_im, …) using vDSP_ctoz.
            paddedFrame.withUnsafeMutableBufferPointer { pPtr in
                guard let p = pPtr.baseAddress else { return }
                p.withMemoryRebound(to: DSPComplex.self, capacity: Self.nFFT / 2) { complexPtr in
                    realParts.withUnsafeMutableBufferPointer { rPtr in
                        imagParts.withUnsafeMutableBufferPointer { iPtr in
                            guard let r = rPtr.baseAddress, let i = iPtr.baseAddress else { return }
                            var split = DSPSplitComplex(realp: r, imagp: i)
                            vDSP_ctoz(complexPtr, 2, &split, 1, vDSP_Length(Self.nFFT / 2))
                            vDSP_fft_zrip(fftSetup, &split, 1, Self.log2N, FFTDirection(FFT_FORWARD))

                            // Power spectrum across all 257 bins.
                            // vDSP packed format: realp[0]=DC, imagp[0]=Nyquist, the rest paired.
                            power[0] = r[0] * r[0]
                            power[Self.nFFT / 2] = i[0] * i[0]
                            // Remaining bins: |X[k]|² = realp[k]² + imagp[k]²
                            // vDSP_zvmags computes squared magnitudes for split-complex
                            // input — but it expects bins 0..n-1; we already handled
                            // 0 and n/2 manually, so loop bins 1..n/2-1.
                            for k in 1 ..< (Self.nFFT / 2) {
                                power[k] = r[k] * r[k] + i[k] * i[k]
                            }
                            // Compensate for vDSP packed-FFT 2× scaling so values match
                            // a textbook |X|² spectrum.
                            var scale: Float = 0.25
                            vDSP_vsmul(power, 1, &scale, &power, 1, vDSP_Length(Self.nBins))
                        }
                    }
                }
            }

            // Mel filterbank: melEnergies = melMatrix × power.
            vDSP_mmul(
                melMatrix, 1,
                power, 1,
                &melEnergies, 1,
                vDSP_Length(Self.nMels), vDSP_Length(1), vDSP_Length(Self.nBins)
            )

            // Floor + log (vForce).
            var floor = Self.logFloor
            vDSP_vsadd(melEnergies, 1, &floor, &melEnergies, 1, vDSP_Length(Self.nMels))
            var n: Int32 = Int32(Self.nMels)
            vvlogf(&melEnergies, melEnergies, &n)

            // Copy frame's 80 mels into the row-major output.
            output.withUnsafeMutableBufferPointer { oPtr in
                guard let o = oPtr.baseAddress else { return }
                o.advanced(by: f * Self.nMels).update(from: melEnergies, count: Self.nMels)
            }
        }

        return (output, nFrames)
    }

    // MARK: - MLMultiArray helpers

    /// Build the `[1, nFrames, 80]` Float16 input array. `features` is the
    /// Float32 mel matrix; we clip to [minFrames, maxFrames] (the model's
    /// `shapeRange`) and zero-pad on the right when there aren't enough frames.
    private func makeInputArray(features: [Float], nFrames: Int) throws -> MLMultiArray {
        let clippedFrames = max(Self.minFrames, min(Self.maxFrames, nFrames))
        let shape: [NSNumber] = [1, NSNumber(value: clippedFrames), NSNumber(value: Self.nMels)]
        let array: MLMultiArray
        do {
            array = try MLMultiArray(shape: shape, dataType: .float16)
        } catch {
            throw EmbedderError.inferenceFailed("MLMultiArray alloc: \(error.localizedDescription)")
        }
        let totalElems = clippedFrames * Self.nMels
        let dst = array.dataPointer.bindMemory(to: Float16.self, capacity: totalElems)
        let validFrames = min(nFrames, clippedFrames)
        let validElems = validFrames * Self.nMels

        // Float32 → Float16 element-wise. (Accelerate has vImage helpers, but
        // for ≤80k floats the straight cast is plenty fast and clearer.)
        features.withUnsafeBufferPointer { src in
            guard let s = src.baseAddress else { return }
            for i in 0 ..< validElems {
                dst[i] = Float16(s[i])
            }
        }
        // Zero-pad if we had fewer than `minFrames`.
        if clippedFrames > validFrames {
            let padStart = validElems
            let padCount = totalElems - padStart
            for i in 0 ..< padCount {
                dst[padStart + i] = 0
            }
        }
        return array
    }

    /// Output is Float16 per the model spec; convert each element to Float32.
    private func unpackEmbedding(_ array: MLMultiArray) throws -> SpeakerEmbedding {
        let total = array.shape.reduce(1) { $0 * $1.intValue }
        guard total == Self.embeddingDim else { throw EmbedderError.invalidOutputShape }

        switch array.dataType {
        case .float16:
            let ptr = array.dataPointer.bindMemory(to: Float16.self, capacity: Self.embeddingDim)
            return (0 ..< Self.embeddingDim).map { Float(ptr[$0]) }
        case .float32:
            let ptr = array.dataPointer.bindMemory(to: Float.self, capacity: Self.embeddingDim)
            return Array(UnsafeBufferPointer(start: ptr, count: Self.embeddingDim))
        default:
            throw EmbedderError.invalidOutputShape
        }
    }

    // MARK: - Mel filterbank matrix (HTK-style triangular filters)

    private static func buildMelMatrix() -> [Float] {
        let fmin: Double = 0
        let fmax = sampleRate / 2 // 8000 Hz Nyquist

        let melMin = hzToMel(fmin)
        let melMax = hzToMel(fmax)
        let nPoints = nMels + 2

        // (nMels + 2) mel-evenly-spaced points, converted back to Hz, then to FFT bin indices.
        let melPoints = (0 ..< nPoints).map { i in
            melMin + (melMax - melMin) * Double(i) / Double(nPoints - 1)
        }
        let bins = melPoints.map { Double(melToHz($0) / sampleRate) * Double(nFFT) }

        var matrix = [Float](repeating: 0, count: nMels * nBins)
        for m in 0 ..< nMels {
            let lo = bins[m]
            let mid = bins[m + 1]
            let hi = bins[m + 2]
            for k in 0 ..< nBins {
                let kk = Double(k)
                let weight: Double
                if kk <= lo || kk >= hi {
                    weight = 0
                } else if kk <= mid {
                    weight = (mid - lo) > 0 ? (kk - lo) / (mid - lo) : 0
                } else {
                    weight = (hi - mid) > 0 ? (hi - kk) / (hi - mid) : 0
                }
                matrix[m * nBins + k] = Float(max(0, weight))
            }
        }
        return matrix
    }

    private static func hzToMel(_ hz: Double) -> Double { 2595 * log10(1 + hz / 700) }
    private static func melToHz(_ mel: Double) -> Double { 700 * (pow(10, mel / 2595) - 1) }
}
