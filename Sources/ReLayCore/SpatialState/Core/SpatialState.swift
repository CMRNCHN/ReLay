import Foundation

/// The authoritative runtime representation of all spatial layout state.
/// All mutations flow through `SpatialStateStore` — never written directly.
public struct SpatialState: Codable {

    /// Monotonically increasing counter. Incremented on every successful mutation.
    public var version: Int

    /// The current workspace model — window frames as ReLay understands them.
    public var workspace: WorkspaceModel

    /// When the system (CGWindowList) was last read to validate or refresh state.
    public var lastSystemSnapshot: Date

    /// True when internal state has been mutated but not yet pushed to macOS.
    public var isDirty: Bool

    public init(workspace: WorkspaceModel) {
        self.version            = 1
        self.workspace          = workspace
        self.lastSystemSnapshot = .distantPast
        self.isDirty            = false
    }
}
