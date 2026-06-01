import Foundation

/// Constructs a Workspace from a live capture.
public enum WorkspaceBuilder {

    public static func build(from windows: [WorkspaceCaptureService.CapturedWindow], name: String) -> Workspace {
        let appLayouts = windows.map { w in
            AppLayout(
                bundleID: w.bundleID,
                windowTitle: w.windowTitle,
                normalizedFrame: w.normalizedFrame,
                displayID: w.displayID
            )
        }
        return Workspace(
            name: name,
            layout: WorkspaceLayout(appLayouts: appLayouts)
        )
    }
}
