import AppKit
import CoreGraphics

/// Main orchestrator: bridges AppIntent to macOS window/workspace state.
/// Snapshot once, mutate locally, push to system — never query AX per-event.
public final class WindowEngine {

    public static let shared = WindowEngine()

    private let snapshotter    = WorkspaceSnapshotter()
    private let mover          = WindowMover()
    private let focusCtrl      = FocusController()
    private let store          = WorkspaceStore.shared

    /// Last captured workspace. Mutated in place by transform operations.
    private(set) public var currentWorkspace: WorkspaceModel?

    /// Debounce guard for restore operations — prevents rapid-fire AX spam.
    private var restoreThrottleDate: Date = .distantPast
    private let restoreMinInterval: TimeInterval = 0.05

    private init() {
        AppLogger.log("window engine initialized", subsystem: "window-engine")
    }

    // MARK: - Capture

    @discardableResult
    public func captureWorkspace(name: String = "Workspace") -> WorkspaceModel {
        let workspace = snapshotter.captureWorkspace(name: name)
        currentWorkspace = workspace
        return workspace
    }

    // MARK: - Restore

    /// Restores every window in `workspace` to its captured frame.
    /// Throttled so burst calls from continuous gestures collapse gracefully.
    public func restore(_ workspace: WorkspaceModel) {
        let now = Date()
        guard now.timeIntervalSince(restoreThrottleDate) >= restoreMinInterval else { return }
        restoreThrottleDate = now

        AppLogger.log("workspace restore windows=\(workspace.windows.count)", subsystem: "window-engine")
        for window in workspace.windows {
            focusCtrl.focus(pid: window.pid)
            mover.move(window: window, to: window.frame)
        }
    }

    /// Capture, persist to `WorkspaceStore`, and return the stored model.
    @discardableResult
    public func captureAndSave(name: String = "Workspace") -> WorkspaceModel {
        let ws = captureWorkspace(name: name)
        store.save(ws)
        return ws
    }

    // MARK: - Workspace Transform

    /// Shifts every window in the current workspace by `delta` and pushes to system.
    /// This is the gesture-driven "move the entire workspace" primitive.
    public func moveWorkspace(delta: CGPoint) {
        guard var workspace = currentWorkspace else {
            AppLogger.log("moveWorkspace called with no current workspace — capturing first", subsystem: "window-engine")
            captureWorkspace()
            return
        }

        workspace.windows = workspace.windows.map { w in
            var updated = w
            updated.frame.origin.x += delta.x
            updated.frame.origin.y += delta.y
            return updated
        }

        // Push to system (throttled internally)
        restore(workspace)
        // Update local model to reflect the new positions
        currentWorkspace = workspace
    }

    // MARK: - Permission Guard

    /// Returns true when Accessibility is granted. Call before using the engine
    /// and fail gracefully if false — the engine will be a no-op without it.
    public static var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }
}
