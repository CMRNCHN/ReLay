import AppKit
import ApplicationServices

// MARK: - Divider Slider
// Seam handle between tiled windows. Currently disabled as a persistent UI —
// the floating pill was sticking around with 0–1 windows on screen. Edge
// linked-resize still works without it. show/showLater are no-ops that clear
// any leftover panels.

final class DividerSliderController {

    private var panels: [NSPanel] = []
    private var generation: UInt64 = 0

    deinit { hideAll() }

    func hideAll() {
        generation &+= 1
        let doomed = panels
        panels.removeAll()
        for panel in doomed {
            panel.animations.removeAll()
            panel.alphaValue = 0
            panel.ignoresMouseEvents = true
            panel.orderOut(nil)
            panel.contentView = nil
            // Keep releasedWhenClosed false; drop our retain and let ARC free it.
        }
    }

    /// Disabled — clears any leftover handle instead of showing a new one.
    func show(between primary: AXUIElement, and companion: AXUIElement) {
        _ = primary
        _ = companion
        hideAll()
    }

    /// Disabled — cancels pending shows and clears leftovers.
    func showLater(between primary: AXUIElement, and companion: AXUIElement, after delay: TimeInterval) {
        _ = primary
        _ = companion
        _ = delay
        hideAll()
    }
}
