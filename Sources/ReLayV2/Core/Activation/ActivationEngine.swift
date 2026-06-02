import Foundation
import AppKit
import ApplicationServices
import Accessibility

/// The only layer that writes AX position/size attributes.
/// Re-enumerates live windows at activation time — never uses a stale snapshot.
/// Window matching: exact bundle+title → partial title contains → bundle-only fallback.
/// Idempotent: only moves windows that differ from their target frame by more than the tolerance.
public final class ActivationEngine {

    private let captureService: WorkspaceCaptureService
    /// Two frames are considered equal if position and size each differ by less than this many points.
    private let tolerance: CGFloat = 4.0

    public init(captureService: WorkspaceCaptureService = WorkspaceCaptureService()) {
        self.captureService = captureService
    }

    public func activate(_ workspace: Workspace) {
        let liveWindows = captureService.captureWindows()
        var moved = 0

        for appLayout in workspace.layout.appLayouts {
            guard let window = match(appLayout: appLayout, in: liveWindows) else { continue }

            let screen = captureService.screenForIdentifier(appLayout.displayID) ?? NSScreen.main
            guard let screen = screen else { continue }

            let targetAXFrame = captureService.flipToAX(appLayout.normalizedFrame.resolved(to: screen.frame))

            // Read current AX frame; skip if already within tolerance
            if let currentAXFrame = captureService.readAXFrame(window.axElement),
               framesEqual(currentAXFrame, targetAXFrame) {
                continue
            }

            applyFrame(window.axElement, frame: targetAXFrame)
            moved += 1
        }

        if moved == 0 {
            print("[ReLay] no-op: '\(workspace.name)' already applied")
        } else {
            print("[ReLay] '\(workspace.name)': moved \(moved) window(s)")
        }
    }

    // MARK: - Equality

    private func framesEqual(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.origin.x - b.origin.x) < tolerance &&
        abs(a.origin.y - b.origin.y) < tolerance &&
        abs(a.size.width - b.size.width) < tolerance &&
        abs(a.size.height - b.size.height) < tolerance
    }

    // MARK: - Window matching

    private func match(appLayout: AppLayout,
                       in windows: [WorkspaceCaptureService.CapturedWindow])
        -> WorkspaceCaptureService.CapturedWindow?
    {
        if let exact = windows.first(where: {
            $0.bundleID == appLayout.bundleID && $0.windowTitle == appLayout.windowTitle
        }) { return exact }

        if !appLayout.windowTitle.isEmpty,
           let partial = windows.first(where: {
               $0.bundleID == appLayout.bundleID
               && ($0.windowTitle.contains(appLayout.windowTitle)
                   || appLayout.windowTitle.contains($0.windowTitle))
           }) { return partial }

        return windows.first(where: { $0.bundleID == appLayout.bundleID })
    }

    // MARK: - AX Write (only site in ReLayV2)

    private func applyFrame(_ element: AXUIElement, frame: CGRect) {
        var pos  = frame.origin
        var size = frame.size
        guard let posVal  = AXValueCreate(.cgPoint, &pos),
              let sizeVal = AXValueCreate(.cgSize,  &size) else { return }
        // size → position → size avoids macOS off-screen clamping
        AXUIElementSetAttributeValue(element, kAXSizeAttribute     as CFString, sizeVal)
        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, posVal)
        AXUIElementSetAttributeValue(element, kAXSizeAttribute     as CFString, sizeVal)
    }
}
