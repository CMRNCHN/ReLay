import AppKit
import ApplicationServices
import CoreGraphics

/// Moves and resizes windows by locating their AXUIElement via CGWindowID.
public final class WindowMover {

    public init() {}

    // MARK: - Public API

    public func move(window: WindowModel, to frame: CGRect) {
        guard let axWindow = findAXWindow(for: window) else {
            AppLogger.log("window-mover: AX element not found id=\(window.id) app=\(window.appBundleID)", subsystem: "window-engine")
            return
        }
        setFrame(axWindow, frame: frame)
    }

    // MARK: - AX Lookup

    /// Locates the AX window element by matching CGWindowID via the `_AXWindowID` attribute.
    /// Falls back to title + approximate frame matching if the private attribute is unavailable.
    func findAXWindow(for model: WindowModel) -> AXUIElement? {
        let axApp = AXUIElementCreateApplication(model.pid)
        AXUIElementSetAttributeValue(axApp, "AXEnhancedUserInterface" as CFString, true as CFTypeRef)

        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &ref) == .success,
              let windows = ref as? [AXUIElement]
        else { return nil }

        let targetID = UInt32(model.id) ?? 0

        // Primary: match on CGWindowID stored as `_AXWindowID`
        if targetID != 0 {
            for w in windows {
                var idRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(w, "_AXWindowID" as CFString, &idRef) == .success,
                   let wid = idRef as? UInt32, wid == targetID {
                    return w
                }
            }
        }

        // Fallback: match by title, then approximate frame
        return windows.first { w in
            if let title = model.title {
                var tRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(w, kAXTitleAttribute as CFString, &tRef) == .success,
                   let wTitle = tRef as? String, wTitle == title {
                    return true
                }
            }
            if let axFrame = axFrame(of: w) {
                return axFrame.origin.distance(to: model.frame.origin) < 8
            }
            return false
        }
    }

    // MARK: - Frame Primitives

    func setFrame(_ window: AXUIElement, frame: CGRect) {
        var pos  = frame.origin
        var size = frame.size
        guard let posVal  = AXValueCreate(.cgPoint, &pos),
              let sizeVal = AXValueCreate(.cgSize,  &size) else { return }
        // size → position → size avoids macOS off-screen clamping
        AXUIElementSetAttributeValue(window, kAXSizeAttribute     as CFString, sizeVal)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posVal)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute     as CFString, sizeVal)
    }

    private func axFrame(of window: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?, sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success
        else { return nil }
        var pos = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(posRef as! AXValue, .cgPoint, &pos),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: pos, size: size)
    }
}

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        let dx = x - other.x, dy = y - other.y
        return sqrt(dx * dx + dy * dy)
    }
}
