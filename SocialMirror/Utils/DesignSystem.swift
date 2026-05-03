import SwiftUI

enum AppColor {
    static let primary = Color(hex: "7F77DD")
    static let cardBackground = Color(.secondarySystemGroupedBackground)
    static let cardBorder = Color(.separator)
    static let recording = Color(hex: "E74C3C")

    static let speakerPalette: [Color] = [
        Color(hex: "7F77DD"),
        Color(hex: "1D9E75"),
        Color(hex: "D85A30"),
        Color(hex: "BA7517"),
        Color(hex: "378ADD"),
    ]

    static func speaker(_ index: Int) -> Color {
        guard index >= 0 else { return Color.gray }
        return speakerPalette[index % speakerPalette.count]
    }
}

enum AppRadius {
    static let card: CGFloat = 12
    static let pill: CGFloat = 20
}

enum AppAnim {
    static let standard: Animation = .easeInOut(duration: 0.3)
    static let snappy: Animation = .easeInOut(duration: 0.15)
}

extension Color {
    /// Hex string like "7F77DD" or "#7F77DD".
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let value = UInt32(cleaned, radix: 16) ?? 0
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

struct CardStyle: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(AppColor.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                    .stroke(AppColor.cardBorder, lineWidth: 0.5)
            )
    }
}

struct PillStyle: ViewModifier {
    let color: Color
    func body(content: Content) -> some View {
        content
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.18))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

extension View {
    func cardStyle(padding: CGFloat = 16) -> some View { modifier(CardStyle(padding: padding)) }
    func pillStyle(color: Color = AppColor.primary) -> some View { modifier(PillStyle(color: color)) }
}

/// Speaker-count "dots" cluster used in lists.
struct SpeakerDots: View {
    let count: Int
    var size: CGFloat = 8
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0 ..< count, id: \.self) { i in
                Circle()
                    .fill(AppColor.speaker(i))
                    .frame(width: size, height: size)
            }
        }
    }
}

/// Small SF Symbol icon + label badge.
struct SessionTypeBadge: View {
    let type: String
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: SessionType(rawValue: type)?.symbol ?? "mic")
                .imageScale(.small)
            Text(type.capitalized)
        }
        .pillStyle()
    }
}

enum SessionType: String, CaseIterable, Identifiable {
    case interview, meeting, negotiation, call, podcast, other

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .interview: "person.crop.rectangle"
        case .meeting: "person.3.fill"
        case .negotiation: "scale.3d"
        case .call: "phone.fill"
        case .podcast: "waveform.badge.mic"
        case .other: "mic"
        }
    }

    var label: String { rawValue.capitalized }

    /// Diarization tuning for this session type. Multi-speaker formats
    /// (podcast, meeting) use shorter segments and a looser cluster
    /// threshold so ECAPA can discriminate; everything else keeps the
    /// 1 s / 10 s / 0.75 production defaults that work for dyadic calls.
    var diarizationConfig: DiarizationConfig {
        switch self {
        case .podcast, .meeting:
            return DiarizationConfig(
                minSegmentSamples: 8_000,    // 0.5 s
                maxSegmentSamples: 32_000,   // 2.0 s
                similarityThreshold: 0.65
            )
        case .interview, .negotiation, .call, .other:
            return .default
        }
    }
}

/// Per-session diarization knobs. Defaults match production
/// (`SpeechSegmentBuffer.default*` + `OnlineSpeakerClusterer`'s 0.75 threshold).
struct DiarizationConfig: Sendable {
    let minSegmentSamples: Int
    let maxSegmentSamples: Int
    let similarityThreshold: Float

    static let `default` = DiarizationConfig(
        minSegmentSamples: SpeechSegmentBuffer.defaultMinSamples,
        maxSegmentSamples: SpeechSegmentBuffer.defaultMaxSamples,
        similarityThreshold: 0.75
    )
}
