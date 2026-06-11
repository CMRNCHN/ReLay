import Foundation
import AppKit
import ApplicationServices
import Accessibility

/// Observes the running application and window state.
/// Event-driven: pushes snapshots when apps launch, terminate, or change focus.
/// Does NOT poll. Does NOT affect window state. Read-only.
final class ContextEngine {

    typealias SnapshotHandler = (AppSnapshot) -> Void
    private var onChange: SnapshotHandler?

    init() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(environmentChanged),
                       name: NSWorkspace.didActivateApplicationNotification, object: nil)
        nc.addObserver(self, selector: #selector(environmentChanged),
                       name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        nc.addObserver(self, selector: #selector(environmentChanged),
                       name: NSWorkspace.didTerminateApplicationNotification, object: nil)
    }

    func onSnapshotChange(_ handler: @escaping SnapshotHandler) {
        onChange = handler
    }

    func captureSnapshot() -> AppSnapshot {
        guard let screen = NSScreen.main else { return .empty }
        let screenBounds = screen.frame
        var windows: [WindowInfo] = []

        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let bundleID = app.bundleIdentifier else { continue }
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetAttributeValue(axApp, "AXEnhancedUserInterface" as CFString, true as CFTypeRef)

            var ref: CFTypeRef?
            guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &ref) == .success,
                  let list = ref as? [AXUIElement] else { continue }

            for axWindow in list {
                guard let frame = axFrame(axWindow), !frame.isEmpty else { continue }

                var minRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(axWindow, kAXMinimizedAttribute as CFString, &minRef) == .success,
                   let isMin = minRef as? Bool, isMin { continue }

                var titleRef: CFTypeRef?
                let title = (AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef) == .success)
                    ? (titleRef as? String ?? "") : ""

                windows.append(WindowInfo(
                    bundleID: bundleID,
                    appName: app.localizedName ?? bundleID,
                    windowTitle: title,
                    normalizedFrame: NormalizedRect.normalize(frame, in: screenBounds),
                    axElement: axWindow
                ))
            }
        }

        return AppSnapshot(timestamp: Date(), windows: windows, screenBounds: screenBounds)
    }

    // MARK: - Private

    @objc private func environmentChanged() {
        let snapshot = captureSnapshot()
        onChange?(snapshot)
    }

    private func axFrame(_ element: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?, sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success else { return nil }
        var position = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(posRef as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }
}
