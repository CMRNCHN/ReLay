import ApplicationServices
import Cocoa

class PreviewManager {
    static let shared = PreviewManager()
    
    private var previewWindow: NSWindow?
    
    private init() {
        setupWindow()
    }
    
    private func setupWindow() {
        let window = NSWindow(contentRect: .zero,
                              styleMask: .borderless,
                              backing: .buffered,
                              defer: false)
        window.level = .popUpMenu // Floating safely above all apps
        window.backgroundColor = .clear
        window.isOpaque = false
        window.ignoresMouseEvents = true
        window.hasShadow = false
        
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .selection
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        
        // Premium styling matching the spec
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 12.0
        visualEffect.layer?.borderWidth = 2.0
        visualEffect.layer?.borderColor = NSColor.white.withAlphaComponent(0.3).cgColor
        
        window.contentView = visualEffect
        self.previewWindow = window
    }
    
    func updateOverlay(currentFrame: CGRect, targetFrame: CGRect, progress: CGFloat, sessionID: String) {
        guard let window = previewWindow else { return }

        let currentFlipped = flipToBottomUp(currentFrame)
        let targetFlipped = flipToBottomUp(targetFrame)
        
        // 1:1 interpolation tracking between current frame and destination
        let dx = (targetFlipped.origin.x - currentFlipped.origin.x) * progress
        let dy = (targetFlipped.origin.y - currentFlipped.origin.y) * progress
        let dw = (targetFlipped.width - currentFlipped.width) * progress
        let dh = (targetFlipped.height - currentFlipped.height) * progress
        
        let activeFrame = CGRect(
            x: currentFlipped.origin.x + dx,
            y: currentFlipped.origin.y + dy,
            width: currentFlipped.width + dw,
            height: currentFlipped.height + dh
        )
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.05 // Tiny smoothing curve to prevent 60hz jitter
            window.animator().setFrame(activeFrame, display: true)
            window.animator().alphaValue = min(0.25, progress * 0.5) // Eases to 25% target
        }
        
        if !window.isVisible {
            window.orderFront(nil)
        }
    }
    
    func commitOverlay(finalFrame: CGRect, sessionID: String) {
        guard let window = previewWindow, window.isVisible else { return }

        let targetFlipped = flipToBottomUp(finalFrame)
        
        // Snap exactly to frame, then fade out after layout engine takes over
        window.setFrame(targetFlipped, display: true)
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.220 // Matches layout engine spring approx
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
            window.animator().alphaValue = 0.0
        } completionHandler: {
            window.orderOut(nil)
        }
    }
    
    func dismiss(animated: Bool, sessionID: String) {
        guard let window = previewWindow, window.isVisible else { return }

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.120 // Spec: "fades out over 120ms simultaneously"
                window.animator().alphaValue = 0.0
            } completionHandler: {
                window.orderOut(nil)
            }
        } else {
            window.alphaValue = 0.0
            window.orderOut(nil)
        }
    }
    
    private func flipToBottomUp(_ rect: CGRect) -> CGRect {
        guard let primaryScreen = NSScreen.screens.first else { return rect }
        var flipped = rect
        // Translates Accessibility (Top-Left) to AppKit (Bottom-Left)
        flipped.origin.y = primaryScreen.frame.height - rect.origin.y - rect.height
        return flipped
    }
}