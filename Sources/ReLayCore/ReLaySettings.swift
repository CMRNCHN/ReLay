import Foundation

/// Centralized UserDefaults access for ReLay settings.
/// Keys match the string keys used in SettingsWindow.
enum ReLaySettings {

    static var hapticsEnabled: Bool {
        let d = UserDefaults.standard
        guard d.object(forKey: "snapHapticsEnabled") != nil else { return true }
        return d.bool(forKey: "snapHapticsEnabled")
    }

    static var centerSnapEnabled: Bool {
        UserDefaults.standard.bool(forKey: "centerSnapEnabled")
    }

    static var upSwipeAction: SwipeAction {
        SwipeAction(rawValue: UserDefaults.standard.string(forKey: "upSwipeAction") ?? "") ?? .fullscreen
    }

    static var downSwipeAction: SwipeAction {
        SwipeAction(rawValue: UserDefaults.standard.string(forKey: "downSwipeAction") ?? "") ?? .minimize
    }

    enum SwipeAction: String {
        case fullscreen
        case minimize
        case center
        case nothing
    }
}
