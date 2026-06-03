import Foundation
import AppKit
import ApplicationServices
import Accessibility

/// Captures the current window layout and produces a saveable Workspace.
/// Single authority for reading window geometry + display assignment.
public final class WorkspaceCaptureService {

    public struct CapturedWindow {
        public let bundleID: String
        public let appName: String
        public let windowTitle: String
        public let axElement: AXUIElement
        public let normalizedFrame: NormalizedRect
        public let displayID: String
    }

    public init() {}

    public func captureWindows() -> [CapturedWindow] {
        var result: [CapturedWindow] = []

        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let bundleID = app.bundleIdentifier else { continue }
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetAttributeValue(axApp, "AXEnhancedUserInterface" as CFString, true as CFTypeRef)

            var ref: CFTypeRef?
            guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &ref) == .success,
                  let list = ref as? [AXUIElement] else { continue }

            for axWindow in list {
                guard let axRect = readAXFrame(axWindow), !axRect.isEmpty else { continue }

                var minRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(axWindow, kAXMinimizedAttribute as CFString, &minRef) == .success,
                   let isMin = minRef as? Bool, isMin { continue }

                var titleRef: CFTypeRef?
                let title = (AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef) == .success)
                    ? (titleRef as? String ?? "") : ""

                let screen = screenContaining(axFrame: axRect) ?? NSScreen.main
                guard let screen = screen else { continue }

                let flipped = flipToAppKit(axRect)
                let normalized = NormalizedRect.normalize(flipped, in: screen.frame)
                let dispID = displayIdentifier(for: screen)

                result.append(CapturedWindow(
                    bundleID: bundleID,
                    appName: app.localizedName ?? bundleID,
                    windowTitle: title,
                    axElement: axWindow,
                    normalizedFrame: normalized,
                    displayID: dispID
                ))
            }
        }

        return result
    }

    // MARK: - Display helpers

    public func screenForIdentifier(_ id: String) -> NSScreen? {
        NSScreen.screens.first { displayIdentifier(for: $0) == id }
    }

    /// Find the screen that most contains an AX-coordinate rect (top-left origin).
    public func screenContaining(axFrame: CGRect) -> NSScreen? {
        let appKitRect = flipToAppKit(axFrame)
        return NSScreen.screens.max {
            $0.frame.intersection(appKitRect).area < $1.frame.intersection(appKitRect).area
        }
    }

    // MARK: - Coordinate conversion

    /// AX uses top-left origin (Quartz/CG flipped). AppKit uses bottom-left.
    /// Converts an AX rect to AppKit screen coordinates.
    public func flipToAppKit(_ axRect: CGRect) -> CGRect {
        guard let primary = NSScreen.screens.first else { return axRect }
        let totalHeight = primary.frame.height + primary.frame.minY
        let appKitY = totalHeight - axRect.origin.y - axRect.size.height
        return CGRect(x: axRect.origin.x, y: appKitY,
                      width: axRect.size.width, height: axRect.size.height)
    }

    /// AppKit → AX coordinate flip (used at activation time before writing to AX API).
    public func flipToAX(_ appKitRect: CGRect) -> CGRect {
        guard let primary = NSScreen.screens.first else { return appKitRect }
        let totalHeight = primary.frame.height + primary.frame.minY
        let axY = totalHeight - appKitRect.origin.y - appKitRect.size.height
        return CGRect(x: appKitRect.origin.x, y: axY,
                      width: appKitRect.size.width, height: appKitRect.size.height)
    }

    public func displayIdentifier(for screen: NSScreen) -> String {
        if let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
            return String(id)
        }
        return screen.localizedName
    }

    // MARK: - AX frame read

    public func readAXFrame(_ element: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?, sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success else { return nil }
        var position = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(posRef as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }
}

private extension CGRect {
    var area: CGFloat { width * height }
}
