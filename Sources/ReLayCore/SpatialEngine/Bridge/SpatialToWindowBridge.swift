import AppKit
import ApplicationServices
import CoreGraphics
import Accessibility

// ONLY allowed dependency on the window layer. Translates SpatialFrames back into
// AX window moves via LayoutOrchestrator. All AX calls are isolated here.
public final class SpatialToWindowBridge {
    public init() {}

    // Moves each (window, frame) pair. Frames must already be in AX coordinate space.
    public func apply(_ pairs: [(window: AXUIElement, frame: SpatialFrame)]) {
        for (window, frame) in pairs {
            LayoutOrchestrator.shared.animateWindowFrame(window, to: frame.cgRect)
        }
    }

    // Single-window variant used by ActionDispatcher.
    public func apply(frame: SpatialFrame, to window: AXUIElement) {
        LayoutOrchestrator.shared.animateWindowFrame(window, to: frame.cgRect)
    }
}
