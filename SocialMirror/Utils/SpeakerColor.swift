import SwiftUI

enum SpeakerColor {
    private static let palette: [(hex: String, color: Color)] = [
        ("#9B59B6", Color(red: 0.608, green: 0.349, blue: 0.714)), // 0 purple
        ("#1ABC9C", Color(red: 0.102, green: 0.737, blue: 0.612)), // 1 teal
        ("#FF6B6B", Color(red: 1.000, green: 0.420, blue: 0.420)), // 2 coral
        ("#F39C12", Color(red: 0.953, green: 0.612, blue: 0.071)), // 3 amber
        ("#3498DB", Color(red: 0.204, green: 0.596, blue: 0.859)), // 4 blue
    ]

    private static let fallbackHex = "#7F8C8D"
    private static let fallbackColor = Color(red: 0.498, green: 0.549, blue: 0.553)

    static func color(for speakerIndex: Int) -> Color {
        guard speakerIndex >= 0, speakerIndex < palette.count else { return fallbackColor }
        return palette[speakerIndex].color
    }

    static func hex(for speakerIndex: Int) -> String {
        guard speakerIndex >= 0, speakerIndex < palette.count else { return fallbackHex }
        return palette[speakerIndex].hex
    }
}
