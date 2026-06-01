import Foundation

/// Constructs a Workspace from a live AppSnapshot.
/// This is the "save current environment" path — no editor, no configuration.
enum WorkspaceBuilder {

    static func build(from snapshot: AppSnapshot, name: String? = nil) -> Workspace {
        let appLayouts = snapshot.windows.map { window in
            AppLayout(bundleID: window.bundleID, normalizedFrame: window.normalizedFrame)
        }
        return Workspace(
            name: name ?? "Workspace",
            layout: WorkspaceLayout(appLayouts: appLayouts)
        )
    }
}
