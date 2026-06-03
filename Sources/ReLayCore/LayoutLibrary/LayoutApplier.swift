import AppKit
import CoreGraphics

/// Applies a LayoutDefinition to the live system.
///
/// Resolves missing apps gracefully: skips unavailable windows without blocking
/// the restore. Focuses each app before moving its windows since some apps reject
/// AX frame writes unless they are active.
public final class LayoutApplier {

    private let mover = WindowMover()

    public init() {}

    public func apply(_ layout: LayoutDefinition) {
        AppLogger.log(
            "layout applier: applying '\(layout.name)' id=\(layout.id) windows=\(layout.windows.count)",
            subsystem: "window-engine"
        )

        // Group by app so we only activate each app once
        let byApp = Dictionary(grouping: layout.windows, by: { $0.appBundleID })

        for (bundleID, windows) in byApp {
            guard runningApp(bundleID: bundleID) != nil else {
                AppLogger.log("layout applier: app not running bundleID=\(bundleID), skipping \(windows.count) windows", subsystem: "window-engine")
                continue
            }

            // Activate app before moving its windows
            activateApp(bundleID: bundleID)

            for window in windows {
                mover.move(window: window, to: window.frame)
            }
        }

        AppLogger.log("layout applier: done", subsystem: "window-engine")
    }

    // MARK: - Private

    private func runningApp(bundleID: String) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundleID }
    }

    private func activateApp(bundleID: String) {
        runningApp(bundleID: bundleID)?.activate(options: [.activateIgnoringOtherApps])
    }
}
