import AppKit
import ApplicationServices
import CoreGraphics

/// Reads current system window state via CGWindowList.
/// Must be called on the main thread (NSWorkspace is not thread-safe).
public final class WindowSnapshotter {

    public init() {}

    // MARK: - Public API

    public func capture(includeMinimized: Bool = false) -> [WindowModel] {
        let cgWindows    = fetchCGWindowInfo()
        let pidToApp     = buildPIDMap()
        var models: [WindowModel] = []

        for info in cgWindows {
            // NSNumber-backed values from CGWindowListCopyWindowInfo bridge cleanly to Int
            guard let cgIDInt  = info[kCGWindowNumber as String] as? Int,
                  let pidInt   = info[kCGWindowOwnerPID as String] as? Int,
                  let layer    = info[kCGWindowLayer as String] as? Int,
                  layer == 0   // normal window layer only
            else { continue }

            let cgID = CGWindowID(cgIDInt)
            let pid  = pid_t(pidInt)

            // Bounds come as a CFDictionary; NSDictionary bridges it safely for CGRectMakeWithDictionaryRepresentation
            guard let boundsDict = info[kCGWindowBounds as String] as? NSDictionary else { continue }
            var frame = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(boundsDict, &frame),
                  frame.width > 1, frame.height > 1
            else { continue }

            // Skip system processes (Dock, menu bar, daemons)
            guard let app = pidToApp[pid],
                  app.activationPolicy == .regular,
                  let bundleID = app.bundleIdentifier
            else { continue }

            let title   = info[kCGWindowName as String] as? String
            let display = displayID(for: frame)

            models.append(WindowModel(
                id:          String(cgID),
                appBundleID: bundleID,
                pid:         pid,
                title:       title,
                frame:       frame,
                displayID:   display,
                spaceID:     nil
            ))
        }

        return models
    }

    // MARK: - Helpers

    private func fetchCGWindowInfo() -> [[String: Any]] {
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        return CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] ?? []
    }

    private func buildPIDMap() -> [pid_t: NSRunningApplication] {
        var map: [pid_t: NSRunningApplication] = [:]
        for app in NSWorkspace.shared.runningApplications {
            map[app.processIdentifier] = app
        }
        return map
    }

    private func displayID(for frame: CGRect) -> CGDirectDisplayID {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        var ids    = [CGDirectDisplayID](repeating: 0, count: 4)
        var count: UInt32 = 0
        CGGetDisplaysWithPoint(center, 4, &ids, &count)
        return count > 0 ? ids[0] : CGMainDisplayID()
    }
}
