import Foundation
import AppKit
import ApplicationServices
import Accessibility

/// The only layer that writes AX position/size attributes.
/// Receives a Workspace + live WindowSnapshot, resolves normalized frames
/// to screen coordinates, and applies them.
final class ActivationEngine {

    func activate(_ workspace: Workspace, snapshot: AppSnapshot) {
        guard let screen = NSScreen.main else { return }
        let screenBounds = screen.frame

        for appLayout in workspace.layout.appLayouts {
            guard let windowInfo = snapshot.windows.first(where: { $0.bundleID == appLayout.bundleID })
            else { continue }

            let frame = appLayout.normalizedFrame.resolved(to: screenBounds)
            applyFrame(windowInfo.axElement, frame: frame)
        }
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
