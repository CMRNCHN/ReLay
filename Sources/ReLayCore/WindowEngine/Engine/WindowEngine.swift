import AppKit
import CoreGraphics

/// Execution layer: reads from SpatialStateCore and pushes frames to macOS.
/// Does NOT own authoritative state — SpatialStateCore is the source of truth.
///
/// Direct gesture-pipeline callers (SpatialTransitionEngine via LayoutOrchestrator)
/// continue to work unchanged. This engine serves the intent-driven path.
public final class WindowEngine {

    public static let shared = WindowEngine()

    private let core       = SpatialStateCore.shared
    private let snapshotter = WorkspaceSnapshotter()
    private let store       = WorkspaceStore.shared

    private init() {
        AppLogger.log("window engine initialized (routes through SpatialStateCore)", subsystem: "window-engine")
    }

    // MARK: - Capture

    @discardableResult
    public func captureWorkspace(name: String = "Workspace") -> WorkspaceModel {
        core.captureFromSystem()
        return core.currentState().workspace
    }

    @discardableResult
    public func captureAndSave(name: String = "Workspace") -> WorkspaceModel {
        let ws = captureWorkspace(name: name)
        store.save(ws)
        return ws
    }

    // MARK: - Restore

    /// Restore a specific saved workspace — bypasses the state core (explicit user action).
    public func restore(_ workspace: WorkspaceModel) {
        AppLogger.log("explicit restore workspace=\(workspace.id) windows=\(workspace.windows.count)", subsystem: "window-engine")
        // Write the target workspace into core, then push
        core.store.mutate { state in
            state.workspace = workspace
            state.isDirty   = true
            state.version  += 1
        }
        core.restoreToSystem()
    }

    // MARK: - Workspace Transform

    /// Shift the current workspace by `delta`. Delegates to SpatialStateCore.
    public func moveWorkspace(delta: CGPoint) {
        core.applyWorkspaceMove(delta: delta)
    }

    // MARK: - Permission Guard

    public static var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }
}
