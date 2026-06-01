import Foundation
import AppKit
import ApplicationServices
import Accessibility

/// The only layer that writes AX position/size attributes.
/// Re-enumerates live windows at activation time — never uses a stale snapshot.
/// Window matching: exact bundle+title → partial title contains → bundle-only fallback.
public final class ActivationEngine {

    private let captureService: WorkspaceCaptureService

    public init(captureService: WorkspaceCaptureService = WorkspaceCaptureService()) {
        self.captureService = captureService
    }

    public func activate(_ workspace: Workspace) {
        let liveWindows = captureService.captureWindows()

        for appLayout in workspace.layout.appLayouts {
            guard let window = match(appLayout: appLayout, in: liveWindows) else { continue }

            let screen = captureService.screenForIdentifier(appLayout.displayID)
                ?? captureService.screenContaining(axFrame: .zero)
                ?? NSScreen.main

            guard let screen = screen else { continue }

            let appKitFrame = appLayout.normalizedFrame.resolved(to: screen.frame)
            let axFrame = captureService.flipToAX(appKitFrame)
            applyFrame(window.axElement, frame: axFrame)
        }
    }

    // MARK: - Window matching

    private func match(appLayout: AppLayout,
                       in windows: [WorkspaceCaptureService.CapturedWindow])
        -> WorkspaceCaptureService.CapturedWindow?
    {
        // Tier 1: exact bundle + exact title
        if let exact = windows.first(where: {
            $0.bundleID == appLayout.bundleID && $0.windowTitle == appLayout.windowTitle
        }) { return exact }

        // Tier 2: exact bundle + title substring match
        if !appLayout.windowTitle.isEmpty,
           let partial = windows.first(where: {
               $0.bundleID == appLayout.bundleID
               && ($0.windowTitle.contains(appLayout.windowTitle)
                   || appLayout.windowTitle.contains($0.windowTitle))
           }) { return partial }

        // Tier 3: bundle-only (first visible window of that app)
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
