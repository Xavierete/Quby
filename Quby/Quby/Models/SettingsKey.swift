import Foundation

enum SettingsKey {
    static let scanSound = "settings.scanSound"
    static let scanHaptics = "settings.scanHaptics"
    static let showDetailsAutomatically = "settings.showDetailsAutomatically"
    static let openWebsitesAutomatically = "settings.openWebsitesAutomatically"
    static let saveHistory = "settings.saveHistory"
    static let hasSeenGuide = "settings.hasSeenGuide"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            scanSound: true,
            scanHaptics: true,
            showDetailsAutomatically: false,
            openWebsitesAutomatically: false,
            saveHistory: true,
            hasSeenGuide: false
        ])
    }

    static func isOn(_ key: String) -> Bool {
        UserDefaults.standard.bool(forKey: key)
    }
}
