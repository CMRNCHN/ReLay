import Foundation

public struct UsageEvent: Codable {
    public enum Action: String, Codable {
        case appFocused         // user switched to this app
        case windowMoved        // user moved a window
        case workspaceApplied   // layout was applied
        case gestureFired       // gesture triggered an intent
        case sessionStarted     // app launched
        case sessionEnded       // app quit or hid
    }

    public let timestamp: Date
    public let appBundleID: String
    public let action: Action
    public let spatialFrame: SpatialFrame?  // nil for non-spatial events

    public init(appBundleID: String,
                action: Action,
                spatialFrame: SpatialFrame? = nil,
                timestamp: Date = Date()) {
        self.timestamp    = timestamp
        self.appBundleID  = appBundleID
        self.action       = action
        self.spatialFrame = spatialFrame
    }
}
