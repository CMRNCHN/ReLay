import Foundation
import CoreGraphics

/// Centralized UserDefaults access for ReLay settings.
public enum ReLaySettings {

    public static let settingsChanged = Notification.Name("ReLaySettingsChanged")
    public static let interceptionToggled = Notification.Name("ReLayInterceptionToggled")

    // MARK: - Keys

    public enum Key {
        public static let lockThreshold = "lockThreshold"
        public static let cancelThreshold = "cancelThreshold"
        public static let actionThreshold = "actionThreshold"
        public static let flickVelocity = "flickVelocity"
        public static let snapDuration = "snapDuration"
        public static let snapHapticsEnabled = "snapHapticsEnabled"
        public static let interceptionEnabled = "interceptionEnabled"
        public static let snapPreviewEnabled = "snapPreviewEnabled"
        public static let snapAnimateEnabled = "snapAnimateEnabled"
    }

    // MARK: - Defaults

    public enum Default {
        public static let lockThreshold: Double = 20
        public static let cancelThreshold: Double = 25
        public static let actionThreshold: Double = 100
        public static let flickVelocity: Double = 800
        public static let snapDuration: Double = 0.28
        public static let snapHapticsEnabled = true
        public static let interceptionEnabled = true
        /// Destination silhouette during swipe — off by default (was the "ghost").
        public static let snapPreviewEnabled = false
        public static let snapAnimateEnabled = true
    }

    // MARK: - Read

    public static var lockThreshold: CGFloat {
        CGFloat(positiveDouble(forKey: Key.lockThreshold, default: Default.lockThreshold))
    }

    public static var cancelThreshold: CGFloat {
        CGFloat(positiveDouble(forKey: Key.cancelThreshold, default: Default.cancelThreshold))
    }

    public static var actionThreshold: CGFloat {
        CGFloat(positiveDouble(forKey: Key.actionThreshold, default: Default.actionThreshold))
    }

    public static var flickVelocity: CGFloat {
        CGFloat(positiveDouble(forKey: Key.flickVelocity, default: Default.flickVelocity))
    }

    public static var snapDuration: TimeInterval {
        positiveDouble(forKey: Key.snapDuration, default: Default.snapDuration)
    }

    public static var hapticsEnabled: Bool {
        bool(forKey: Key.snapHapticsEnabled, default: Default.snapHapticsEnabled)
    }

    public static var interceptionEnabled: Bool {
        bool(forKey: Key.interceptionEnabled, default: Default.interceptionEnabled)
    }

    public static var snapPreviewEnabled: Bool {
        bool(forKey: Key.snapPreviewEnabled, default: Default.snapPreviewEnabled)
    }

    public static var snapAnimateEnabled: Bool {
        bool(forKey: Key.snapAnimateEnabled, default: Default.snapAnimateEnabled)
    }

    // MARK: - Write

    public static func set(_ value: Double, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
        postSettingsChanged()
    }

    public static func set(_ value: Bool, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
        postSettingsChanged()
    }

    public static func resetAll() {
        set(Default.lockThreshold, forKey: Key.lockThreshold)
        set(Default.cancelThreshold, forKey: Key.cancelThreshold)
        set(Default.actionThreshold, forKey: Key.actionThreshold)
        set(Default.flickVelocity, forKey: Key.flickVelocity)
        set(Default.snapDuration, forKey: Key.snapDuration)
        set(Default.snapHapticsEnabled, forKey: Key.snapHapticsEnabled)
        set(Default.interceptionEnabled, forKey: Key.interceptionEnabled)
        set(Default.snapPreviewEnabled, forKey: Key.snapPreviewEnabled)
        set(Default.snapAnimateEnabled, forKey: Key.snapAnimateEnabled)
    }

    public static func postSettingsChanged() {
        NotificationCenter.default.post(name: settingsChanged, object: nil)
    }

    // MARK: - Helpers

    private static func positiveDouble(forKey key: String, default defaultValue: Double) -> Double {
        let stored = UserDefaults.standard.double(forKey: key)
        return stored > 0 ? stored : defaultValue
    }

    private static func bool(forKey key: String, default defaultValue: Bool) -> Bool {
        guard UserDefaults.standard.object(forKey: key) != nil else { return defaultValue }
        return UserDefaults.standard.bool(forKey: key)
    }
}
