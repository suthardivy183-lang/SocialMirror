import UIKit

/// Thin wrapper around `UINotificationFeedbackGenerator` so call sites stay
/// readable. All entry points are MainActor-safe (UIFeedbackGenerator must be
/// driven on the main thread).
enum Haptics {
    @MainActor
    static func notify(_ kind: UINotificationFeedbackGenerator.FeedbackType) {
        let gen = UINotificationFeedbackGenerator()
        gen.prepare()
        gen.notificationOccurred(kind)
    }

    @MainActor
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        let gen = UIImpactFeedbackGenerator(style: style)
        gen.prepare()
        gen.impactOccurred()
    }
}
