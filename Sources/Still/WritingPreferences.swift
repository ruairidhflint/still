import Foundation

extension Notification.Name {
    static let writingPreferencesChanged = Notification.Name("StillWritingPreferencesChanged")
}

final class WritingPreferences: NSObject {
    static let shared = WritingPreferences()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults; super.init() }

    var checkSpelling: Bool {
        get { defaults.object(forKey: "checkSpellingWhileTyping") as? Bool ?? true }
        set {
            defaults.set(newValue, forKey: "checkSpellingWhileTyping")
            NotificationCenter.default.post(name: .writingPreferencesChanged, object: self)
        }
    }
}
