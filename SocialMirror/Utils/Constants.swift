import Foundation

nonisolated enum UserDefaultsKey {
    static let saveAudioEnabled = "saveAudioEnabled"
    static let autoDeleteAudioDays = "autoDeleteAudioDays"
    // 0 = never, 30 = 30 days, 90 = 90 days
}
