import Cocoa
import ApplicationServices
import Accessibility

// MARK: - AXWindowOps
// Raw AX read/write primitives only.
// No system queries (NSScreen). No UI logic. No animation. No decisions.

enum AXWindowOps {

    // MARK: - Read

    static func frame(_ window: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?, sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute     as CFString, &sizeRef) == .success
        else { return nil }
        var pos = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(posRef  as! AXValue, .cgPoint, &pos),
              AXValueGetValue(sizeRef as! AXValue, .cgSize,  &size)
        else { return nil }
        return CGRect(origin: pos, size: size)
    }

    static func title(_ window: AXUIElement) -> String {
        var ref: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &ref) == .success,
           let t = ref as? String, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return t
        }
        return "Window"
    }

    static func frontmost() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var ref: CFTypeRef?
        if AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &ref) == .success {
            return (ref as! AXUIElement)
        }
        if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &ref) == .success,
           let list = ref as? [AXUIElement], let first = list.first { return first }
        return nil
    }

    static func allVisible() -> [AXUIElement] {
        var result: [AXUIElement] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetAttributeValue(axApp, "AXEnhancedUserInterface" as CFString, true as CFTypeRef)
            var ref: CFTypeRef?
            guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &ref) == .success,
                  let list = ref as? [AXUIElement] else { continue }
            for win in list {
                var r: CFTypeRef?
                if AXUIElementCopyAttributeValue(win, kAXMinimizedAttribute as CFString, &r) == .success,
                   (r as? Bool) == true { continue }
                result.append(win)
            }
        }
        return result
    }

    // MARK: - Write

    @discardableResult
    static func setFrame(_ window: AXUIElement, _ rect: CGRect) -> Bool {
        var pos = rect.origin, size = rect.size
        guard let posV  = AXValueCreate(.cgPoint, &pos),
              let sizeV = AXValueCreate(.cgSize,  &size) else { return false }
        let r1 = AXUIElementSetAttributeValue(window, kAXSizeAttribute     as CFString, sizeV)
        let r2 = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posV)
        let r3 = AXUIElementSetAttributeValue(window, kAXSizeAttribute     as CFString, sizeV)
        return r1 == .success && r2 == .success && r3 == .success
    }

    @discardableResult
    static func setSize(_ window: AXUIElement, _ size: CGSize) -> Bool {
        var s = size
        guard let sizeV = AXValueCreate(.cgSize, &s) else { return false }
        return AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeV) == .success
    }
}
