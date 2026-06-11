import Foundation

/// Assembles a full WorkspaceModel from current system state.
public final class WorkspaceSnapshotter {

    private let windowSnapshotter = WindowSnapshotter()

    public init() {}

    public func captureWorkspace(name: String = "Workspace") -> WorkspaceModel {
        let windows = windowSnapshotter.capture()
        AppLogger.log("workspace captured windows=\(windows.count)", subsystem: "window-engine")
        return WorkspaceModel(
            id:        UUID().uuidString,
            name:      name,
            windows:   windows,
            createdAt: Date()
        )
    }
}
