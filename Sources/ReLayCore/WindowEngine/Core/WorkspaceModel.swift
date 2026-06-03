import Foundation

/// Full layout snapshot — all visible windows on all displays at a point in time.
public struct WorkspaceModel: Codable, Hashable {
    public let id: String
    public let name: String
    /// Mutable so the engine can apply in-place transforms without full re-capture.
    public var windows: [WindowModel]
    public let createdAt: Date
}
