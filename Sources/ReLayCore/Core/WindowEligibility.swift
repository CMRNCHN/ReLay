import AppKit
import ApplicationServices
import CoreGraphics

// MARK: - Window Eligibility
// Single gate for "is this a real, tileable document window?"
// Menu-bar extras, popups, HUDs, and floating inspectors must not inflate
// tile counts or get forced into full tile frames.

enum WindowEligibility {

    /// Absolute floor (matches AX write floor).
    static let minWidth: CGFloat = AXWindowOps.minWritableWidth
    static let minHeight: CGFloat = AXWindowOps.minWritableHeight

    /// Must cover at least this fraction of the usable screen — kills compact
    /// dropdown panels that still clear the absolute floor.
    static let minAreaFraction: CGFloat = 0.15

    /// Alternate path for tall/narrow or wide/short document windows (thirds,
    /// 2×2 cells) that may sit just under the area cut when gaps are large.
    static let minWidthFraction: CGFloat = 0.32
    static let minHeightFraction: CGFloat = 0.40

    // MARK: - Geometry (pure)

    /// Whether `frame` is large enough on `screen` to be treated as a tileable
    /// document window — not a palette, menu-bar dropdown, or toast.
    static func isSubstantialFrame(_ frame: CGRect, on screen: CGRect) -> Bool {
        guard !frame.isEmpty, !screen.isEmpty else { return false }
        guard frame.width >= minWidth, frame.height >= minHeight else { return false }

        let overlap = frame.intersection(screen)
        guard overlap.width >= minWidth * 0.9,
              overlap.height >= minHeight * 0.9
        else { return false }

        let screenArea = screen.width * screen.height
        guard screenArea > 0 else { return false }
        let areaFraction = (overlap.width * overlap.height) / screenArea
        if areaFraction >= minAreaFraction { return true }

        let widthFraction = overlap.width / screen.width
        let heightFraction = overlap.height / screen.height
        return widthFraction >= minWidthFraction && heightFraction >= minHeightFraction
    }

    // MARK: - App

    /// Menu-bar extras and background agents are `.accessory` / `.prohibited`.
    static func isRegularApp(pid: pid_t) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return false }
        return app.activationPolicy == .regular
    }

    static func isMutableApp(bundleID: String) -> Bool {
        WindowMutabilityPolicy.decision(for: bundleID) == .allow
    }

    static func isTileableApp(pid: pid_t, bundleID: String? = nil) -> Bool {
        guard isRegularApp(pid: pid) else { return false }
        let bid = bundleID
            ?? NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
            ?? ""
        return isMutableApp(bundleID: bid)
    }

    // MARK: - AX window

    /// Full check before any auto-tile / companion / linked-resize write.
    static func isTileableWindow(_ window: AXUIElement, on screen: CGRect) -> Bool {
        guard AXWindowOps.isStandardWindow(window) else { return false }
        // Non-resizable windows keep their size — never force them into a tile.
        if AXWindowOps.isResizable(window) == false { return false }
        guard let frame = AXWindowOps.frame(window),
              isSubstantialFrame(frame, on: screen)
        else { return false }

        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        return isTileableApp(pid: pid)
    }

    /// CG-side prefilter (no AX). Used to ignore menu-bar / tiny overlays before
    /// settling a newcomer for auto-layout.
    static func isTileableCGEntry(pid: pid_t, bounds: CGRect, on screen: CGRect) -> Bool {
        guard isTileableApp(pid: pid) else { return false }
        return isSubstantialFrame(bounds, on: screen)
    }
}
