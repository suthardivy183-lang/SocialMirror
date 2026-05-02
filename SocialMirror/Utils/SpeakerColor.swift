import SwiftUI

enum SpeakerColor {
    /// Canonical palette — kept in sync with `AppColor.speakerPalette`.
    private static let palette: [(hex: String, color: Color)] = [
        ("#7F77DD", Color(hex: "7F77DD")), // 0 purple
        ("#1D9E75", Color(hex: "1D9E75")), // 1 green
        ("#D85A30", Color(hex: "D85A30")), // 2 coral
        ("#BA7517", Color(hex: "BA7517")), // 3 amber
        ("#378ADD", Color(hex: "378ADD")), // 4 blue
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
