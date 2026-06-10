import AppKit
import CoreGraphics
import Accessibility

// Reads the live macOS window state via LayoutOrchestrator and populates a SpatialState.
public final class SpatialStateReconciler {
    public init() {}

    public func snapshot() -> SpatialState {
        let windows = LayoutOrchestrator.shared.getAllVisibleWindows()
        var models: [WindowModel] = []

        for window in windows {
            guard let frame = LayoutOrchestrator.shared.getWindowFrame(window) else { continue }
            var pid: pid_t = 0
            AXUIElementGetPid(window, &pid)
            guard let app = NSRunningApplication(processIdentifier: pid) else { continue }
            let bundleID = app.bundleIdentifier ?? "pid-\(pid)"
            let title = LayoutOrchestrator.shared.windowTitle(for: window)
            let display = displayID(for: frame)

            models.append(WindowModel(
                id: "\(bundleID)|\(title)",
                appBundleID: bundleID,
                pid: pid,
                title: title,
                frame: frame,
                displayID: display,
                spaceID: nil
            ))
        }

        let workspace = WorkspaceModel(
            id: UUID().uuidString,
            name: "Live",
            windows: models,
            createdAt: Date()
        )
        return SpatialState(workspace: workspace)
    }

    private func displayID(for frame: CGRect) -> CGDirectDisplayID {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        var ids = [CGDirectDisplayID](repeating: 0, count: 4)
        var count: UInt32 = 0
        CGGetDisplaysWithPoint(center, 4, &ids, &count)
        return count > 0 ? ids[0] : CGMainDisplayID()
    }
}
