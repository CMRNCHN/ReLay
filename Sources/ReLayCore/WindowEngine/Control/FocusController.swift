import AppKit

/// Brings an application to the foreground before performing window operations.
/// Focus must precede AX moves on some apps that reject off-focus AX writes.
public final class FocusController {

    public init() {}

    public func focus(appBundleID: String) {
        guard let app = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == appBundleID })
        else { return }
        app.activate(options: [.activateIgnoringOtherApps])
    }

    /// Focus by PID — faster when already known from a WindowModel.
    public func focus(pid: pid_t) {
        guard let app = NSWorkspace.shared.runningApplications
            .first(where: { $0.processIdentifier == pid })
        else { return }
        app.activate(options: [.activateIgnoringOtherApps])
    }
}
