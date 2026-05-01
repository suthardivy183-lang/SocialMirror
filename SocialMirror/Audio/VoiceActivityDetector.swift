import Accelerate
import Foundation

/// Per-frame state machine deciding whether the current audio frame is speech,
/// silence, or marks the trailing-pause boundary at the end of a speech segment.
///
/// Hysteresis: requires `minSpeechFrames` consecutive loud frames to enter
/// speaking and `minSilenceFrames` consecutive quiet frames to leave it.
/// `.segmentEnd` is emitted exactly once on the silent frame that flips the
/// state from speaking → silent.
nonisolated struct VoiceActivityDetector: Sendable {
    enum VADState: Sendable, Equatable {
        case silence
        case speech
        case segmentEnd
    }

    var silenceThreshold: Float = 0.002
    var minSpeechFrames: Int = 8
    var minSilenceFrames: Int = 15

    private(set) var isSpeaking: Bool = false
    private var consecutiveSpeech: Int = 0
    private var consecutiveSilence: Int = 0

    init(
        silenceThreshold: Float = 0.002,
        minSpeechFrames: Int = 8,
        minSilenceFrames: Int = 15
    ) {
        self.silenceThreshold = silenceThreshold
        self.minSpeechFrames = minSpeechFrames
        self.minSilenceFrames = minSilenceFrames
    }

    /// Process a single audio frame (typically 320 samples / 20 ms at 16 kHz)
    /// and return the resulting VAD state.
    mutating func processingFrame(_ samples: [Float]) -> VADState {
        let energy = Self.rms(samples)
        let isLoud = energy >= silenceThreshold

        if isLoud {
            consecutiveSilence = 0
            consecutiveSpeech &+= 1
            if !isSpeaking, consecutiveSpeech >= minSpeechFrames {
                isSpeaking = true
            }
            return isSpeaking ? .speech : .silence
        } else {
            consecutiveSpeech = 0
            consecutiveSilence &+= 1
            if isSpeaking, consecutiveSilence >= minSilenceFrames {
                isSpeaking = false
                return .segmentEnd
            }
            return .silence
        }
    }

    /// Reset all state. Call between sessions.
    mutating func reset() {
        isSpeaking = false
        consecutiveSpeech = 0
        consecutiveSilence = 0
    }

    /// RMS energy via Accelerate (`vDSP_rmsqv`).
    static func rms(_ samples: [Float]) -> Float {
        var result: Float = 0
        samples.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return }
            vDSP_rmsqv(base, 1, &result, vDSP_Length(samples.count))
        }
        return result
    }
}
