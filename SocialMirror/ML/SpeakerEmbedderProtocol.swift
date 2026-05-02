import Foundation

/// Anything that can turn a speech segment into a fixed-length speaker
/// embedding. Implemented by `MockSpeakerEmbedder` for simulator/testing
/// and `CoreMLSpeakerEmbedder` for production ECAPA-TDNN inference.
protocol SpeakerEmbeddingProvider: Sendable {
    func embed(_ segment: SpeechSegment) async throws -> SpeakerEmbedding
}

enum EmbedderError: Error, CustomStringConvertible {
    case modelNotFound
    case inferenceFailed(String)
    case invalidOutputShape

    var description: String {
        switch self {
        case .modelNotFound:
            return "ECAPA model not found in app bundle"
        case .inferenceFailed(let detail):
            return "ECAPA inference failed: \(detail)"
        case .invalidOutputShape:
            return "ECAPA produced an embedding of unexpected shape"
        }
    }
}
