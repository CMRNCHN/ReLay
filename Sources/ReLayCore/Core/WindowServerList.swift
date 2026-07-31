import CoreGraphics

// MARK: - Window Server List
// CGWindowList reads. Separate from AXWindowOps because this is the window
// server's view, not Accessibility's: it is ordered front-to-back and only
// includes windows on the *current* Space, which AX cannot tell us.
//
// Bounds use Quartz / AX top-left space (same as CGEvent.location and
// AXUIElement frames). Do not flip — kCGWindowBounds origin is upper-left.

enum WindowServerList {

    struct Entry {
        let pid: pid_t
        /// Quartz / AX top-left global coordinates.
        let bounds: CGRect
    }

    /// Front-to-back, current Space only, desktop elements excluded.
    static func onScreenOrder() -> [Entry] {
        let info = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] ?? []

        return info.compactMap { entry in
            guard let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                  let b = entry[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = b["X"], let y = b["Y"], let w = b["Width"], let h = b["Height"]
            else { return nil }
            return Entry(pid: pid, bounds: CGRect(x: x, y: y, width: w, height: h))
        }
    }

    /// Frontmost on-screen window whose bounds (optionally expanded) contain `point`.
    /// Skips tiny layers (menus, tooltips) that sit above real windows in the list.
    static func topmost(
        at point: CGPoint,
        in order: [Entry],
        expandBy slack: CGFloat = 0,
        minSize: CGFloat = 80
    ) -> Entry? {
        order.first { entry in
            guard entry.bounds.width >= minSize, entry.bounds.height >= minSize else { return false }
            return entry.bounds.insetBy(dx: -slack, dy: -slack).contains(point)
        }
    }

    /// Whether two frames describe the same window within `tolerance`.
    static func framesMatch(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 4) -> Bool {
        abs(a.minX - b.minX) < tolerance
            && abs(a.minY - b.minY) < tolerance
            && abs(a.width - b.width) < tolerance
            && abs(a.height - b.height) < tolerance
    }

    /// Index of an AX window in the front-to-back order, or nil when the window
    /// server does not report it — which means it lives on another Space.
    static func zOrder(of frame: CGRect, pid: pid_t, in order: [Entry], tolerance: CGFloat = 4) -> Int? {
        order.firstIndex {
            $0.pid == pid && framesMatch($0.bounds, frame, tolerance: tolerance)
        }
    }
}
