import ApplicationServices
import Cocoa

class PreviewManager {
    static let shared = PreviewManager()
    
    private var previewWindow: NSWindow?
    private var targetWindow: NSWindow?
    
    private init() {
        setupWindows()
    }
    
    private func setupWindows() {
        previewWindow = createOverlayWindow(material: .selection, borderOpacity: 0.3)
        targetWindow = createOverlayWindow(material: .underWindowBackground, borderOpacity: 0.1)
    }

    private func createOverlayWindow(material: NSVisualEffectView.Material, borderOpacity: CGFloat) -> NSWindow {
        let window = NSWindow(contentRect: .zero,
                              styleMask: .borderless,
                              backing: .buffered,
                              defer: false)
        window.level = .popUpMenu
        window.backgroundColor = .clear
        window.isOpaque = false
        window.ignoresMouseEvents = true
        window.hasShadow = false
        
        let visualEffect = NSVisualEffectView()
        visualEffect.material = material
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 12.0
        visualEffect.layer?.borderWidth = 1.5
        visualEffect.layer?.borderColor = NSColor.white.withAlphaComponent(borderOpacity).cgColor
        
        // Add a subtle inner glow/shadow to make the edge stand out
        visualEffect.layer?.shadowColor = NSColor.white.cgColor
        visualEffect.layer?.shadowOffset = .zero
        visualEffect.layer?.shadowRadius = 4.0
        visualEffect.layer?.shadowOpacity = 0.0
        
        window.contentView = visualEffect
        return window
    }
    
    func updateOverlay(currentFrame: CGRect, targetFrame: CGRect, progress: CGFloat) {
        guard let window = previewWindow, let targetWin = targetWindow else { return }
        
        let currentFlipped = flipToBottomUp(currentFrame)
        let targetFlipped = flipToBottomUp(targetFrame)
        
        // Show/Update Target Window (the snap destination)
        if !targetWin.isVisible {
            targetWin.setFrame(targetFlipped, display: true)
            targetWin.alphaValue = 0.0
            targetWin.orderFront(nil)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                targetWin.animator().alphaValue = 0.15
            }
        } else {
            targetWin.animator().setFrame(targetFlipped, display: true)
        }

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
            window.animator().alphaValue = min(0.35, progress * 0.6) // Eases to 35% target
            
            // Pulse the border/glow as we reach commitment
            if let layer = window.contentView?.layer {
                layer.borderColor = NSColor.white.withAlphaComponent(0.3 + (progress * 0.4)).cgColor
                layer.shadowOpacity = Float(progress * 0.5)
            }
        }
        
        if !window.isVisible {
            window.orderFront(nil)
        }
    }
    
    func commitOverlay(finalFrame: CGRect) {
        guard let window = previewWindow, window.isVisible else { return }
        
        let targetFlipped = flipToBottomUp(finalFrame)
        
        // Hide target window immediately
        targetWindow?.alphaValue = 0.0
        targetWindow?.orderOut(nil)

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
    
    func dismiss(animated: Bool) {
        let windows = [previewWindow, targetWindow].compactMap { $0 }
        
        for window in windows {
            guard window.isVisible else { continue }
            
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
    }
    
    private func flipToBottomUp(_ rect: CGRect) -> CGRect {
        // Accessibility coordinates are Top-Left (Y decreases as you go up, but macOS screen coords have Y increasing up)
        // Actually, AX coordinates (0,0) are Top-Left of the PRIMARY screen.
        // AppKit coordinates (0,0) are Bottom-Left of the PRIMARY screen.
        
        guard let primaryScreen = NSScreen.screens.first else { return rect }
        let primaryHeight = primaryScreen.frame.height
        
        var flipped = rect
        flipped.origin.y = primaryHeight - rect.origin.y - rect.height
        return flipped
    }
}