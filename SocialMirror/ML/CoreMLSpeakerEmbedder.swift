import CoreML
import Foundation
import os

/// Production speaker embedder backed by a Core ML ECAPA-TDNN model
/// (`ECAPA.mlpackage` in the app bundle, compiled to `ECAPA.mlmodelc` at build).
///
/// Input:  MLMultiArray shape [1, sampleCount] Float32 (raw 16 kHz PCM)
/// Output: MLMultiArray shape [1, 192] Float32
///
/// Throws `EmbedderError.modelNotFound` if the bundle has no model — handy
/// during early development where only the mock embedder exists.
nonisolated final class CoreMLSpeakerEmbedder: SpeakerEmbeddingProvider, @unchecked Sendable {
    private static let log = Logger(subsystem: "com.divy.SocialMirror", category: "Embedder")

    /// Override these if your model uses different feature names.
    var inputFeatureName: String = "audio_input"
    var outputFeatureName: String = "embedding"

    private let model: MLModel

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
        Self.log.info("Loaded ECAPA model from \(url.lastPathComponent, privacy: .public)")
    }

    func embed(_ segment: SpeechSegment) async throws -> SpeakerEmbedding {
        let start = CFAbsoluteTimeGetCurrent()

        let input = try makeInput(from: segment.samples)
        let provider: MLFeatureProvider
        do {
            let dict: [String: MLFeatureValue] = [
                inputFeatureName: MLFeatureValue(multiArray: input),
            ]
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
        Self.log.debug("ECAPA inference: \(elapsedMs, format: .fixed(precision: 2), privacy: .public) ms")
        return embedding
    }

    // MARK: - Helpers

    private func makeInput(from samples: [Float]) throws -> MLMultiArray {
        let shape: [NSNumber] = [1, NSNumber(value: samples.count)]
        let array: MLMultiArray
        do {
            array = try MLMultiArray(shape: shape, dataType: .float32)
        } catch {
            throw EmbedderError.inferenceFailed("MLMultiArray alloc: \(error.localizedDescription)")
        }
        let dst = array.dataPointer.bindMemory(to: Float.self, capacity: samples.count)
        samples.withUnsafeBufferPointer { src in
            guard let s = src.baseAddress else { return }
            dst.update(from: s, count: samples.count)
        }
        return array
    }

    private func unpackEmbedding(_ array: MLMultiArray) throws -> SpeakerEmbedding {
        let total = array.shape.reduce(1) { $0 * $1.intValue }
        guard total == 192 else { throw EmbedderError.invalidOutputShape }
        guard array.dataType == .float32 else { throw EmbedderError.invalidOutputShape }
        let ptr = array.dataPointer.bindMemory(to: Float.self, capacity: 192)
        return Array(UnsafeBufferPointer(start: ptr, count: 192))
    }
}
