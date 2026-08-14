import AppKit
import ApplicationServices
import CoreGraphics

// MARK: - Title bar hit test
// Scroll gestures count when the cursor is in a window's title bar —
// including inactive (background) windows under the cursor.
// Menu-bar extras, dialogs, and floating panels are ignored.

enum TitleBarHitTest {

    /// Draggable title strip height (unified toolbar / Electron title bars).
    static let height: CGFloat = 52

    /// Traffic-light inset — gestures in this left strip are ignored so close/minimize/zoom still work.
    static let trafficLightInset: CGFloat = 78

    static func isGestureAllowed(at point: CGPoint) -> Bool {
        windowForGesture(at: point) != nil
    }

    /// Window whose title bar contains `point`, preferring the topmost window under the cursor.
    static func windowForGesture(at point: CGPoint) -> AXUIElement? {
        if let window = AXWindowOps.window(at: point),
           isGestureTarget(window),
           let frame = AXWindowOps.frame(window),
           titleBarRect(for: frame).contains(point) {
            return window
        }

        // Fallback when element-at-position misses (Electron / metal views).
        // WindowServerList bounds are already in AX / top-left space.
        let order = WindowServerList.onScreenOrder()
        for entry in order {
            guard WindowEligibility.isRegularApp(pid: entry.pid) else { continue }
            guard titleBarRect(for: entry.bounds).contains(point) else { continue }
            if let win = AXWindowOps.window(pid: entry.pid, matching: entry.bounds),
               isGestureTarget(win),
               let frame = AXWindowOps.frame(win),
               titleBarRect(for: frame).contains(point) {
                return win
            }
        }
        return nil
    }

    static func titleBarRect(for windowFrame: CGRect) -> CGRect {
        let barHeight = min(height, windowFrame.height)
        return CGRect(
            x: windowFrame.minX + trafficLightInset,
            y: windowFrame.minY,
            width: max(0, windowFrame.width - trafficLightInset),
            height: barHeight
        )
    }

    private static func isGestureTarget(_ window: AXUIElement) -> Bool {
        guard AXWindowOps.isStandardWindow(window) else { return false }
        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        return WindowEligibility.isTileableApp(pid: pid)
    }
}
