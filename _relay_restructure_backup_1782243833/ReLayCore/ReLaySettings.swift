import Foundation

/// Centralized UserDefaults access for ReLay settings.
/// Keys match the string keys used in SettingsWindow.
enum ReLaySettings {

    static var hapticsEnabled: Bool {
        let d = UserDefaults.standard
        guard d.object(forKey: "snapHapticsEnabled") != nil else { return true }
        return d.bool(forKey: "snapHapticsEnabled")
    }
}
