import Foundation
import Testing
@testable import SocialMirror

struct VoiceActivityDetectorTests {
    private static let frameSize = 320 // 20 ms at 16 kHz

    /// 320 samples of pure zeros.
    private static func silenceFrame() -> [Float] {
        Array(repeating: 0, count: frameSize)
    }

    /// 320 samples of a sine wave at the given amplitude (0...1).
    private static func sineFrame(amplitude: Float = 0.5, frequency: Float = 440, sampleRate: Float = 16_000) -> [Float] {
        let twoPi = 2 * Float.pi
        return (0 ..< frameSize).map { i in
            amplitude * sin(twoPi * frequency * Float(i) / sampleRate)
        }
    }

    @Test func pureSilenceAlwaysReturnsSilence() {
        var vad = VoiceActivityDetector()
        let silence = Self.silenceFrame()
        for _ in 0 ..< 50 {
            #expect(vad.processingFrame(silence) == .silence)
        }
        #expect(vad.isSpeaking == false)
    }

    @Test func sineBurstReturnsSpeechAfterEightFrames() {
        var vad = VoiceActivityDetector()
        let voice = Self.sineFrame()

        // Frames 1..7: still ramping up — should be .silence (below hysteresis).
        for _ in 0 ..< 7 {
            #expect(vad.processingFrame(voice) == .silence)
            #expect(vad.isSpeaking == false)
        }

        // Frame 8: crosses the minSpeechFrames threshold.
        #expect(vad.processingFrame(voice) == .speech)
        #expect(vad.isSpeaking == true)

        // Subsequent frames remain .speech.
        for _ in 0 ..< 5 {
            #expect(vad.processingFrame(voice) == .speech)
        }
    }

    @Test func burstThenSilenceEmitsSegmentEndAfterFifteenSilentFrames() {
        var vad = VoiceActivityDetector()
        let voice = Self.sineFrame()
        let silence = Self.silenceFrame()

        // Push enough voice frames to enter speaking state.
        for _ in 0 ..< 10 {
            _ = vad.processingFrame(voice)
        }
        #expect(vad.isSpeaking == true)

        // Silent frames 1..14 should return .silence (still in speaking state under hysteresis).
        for _ in 0 ..< 14 {
            #expect(vad.processingFrame(silence) == .silence)
        }

        // 15th silent frame crosses minSilenceFrames → .segmentEnd, isSpeaking flips false.
        #expect(vad.processingFrame(silence) == .segmentEnd)
        #expect(vad.isSpeaking == false)

        // Further silence is just .silence.
        #expect(vad.processingFrame(silence) == .silence)
    }

    @Test func resetClearsAllState() {
        var vad = VoiceActivityDetector()
        let voice = Self.sineFrame()
        for _ in 0 ..< 10 { _ = vad.processingFrame(voice) }
        #expect(vad.isSpeaking == true)

        vad.reset()
        #expect(vad.isSpeaking == false)

        // After reset we must again accumulate 8 frames before .speech.
        let silence = Self.silenceFrame()
        #expect(vad.processingFrame(silence) == .silence)
        for _ in 0 ..< 7 {
            #expect(vad.processingFrame(voice) == .silence)
        }
        #expect(vad.processingFrame(voice) == .speech)
    }
}
