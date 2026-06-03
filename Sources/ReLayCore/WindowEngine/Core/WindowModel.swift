import CoreGraphics

/// Snapshot of a single on-screen window, sufficient for capture and restore.
public struct WindowModel: Codable, Hashable {
    /// CGWindowID as a string — stable for the lifetime of the window.
    public let id: String
    public let appBundleID: String
    /// Process ID at capture time. Used to look up the AX element on restore.
    public let pid: pid_t
    public let title: String?

    public var frame: CGRect
    public let displayID: CGDirectDisplayID
    /// Space ID is unavailable without private APIs; reserved for future use.
    public let spaceID: Int?
}
