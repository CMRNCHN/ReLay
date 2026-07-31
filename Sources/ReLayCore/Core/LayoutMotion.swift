import AppKit
import ApplicationServices

// MARK: - Layout Motion
// Choreographs multi-window moves so auto-organize doesn't look like the
// desk is "thinking" — destinations appear together, AX writes land in one
// burst, then the hints fade as one.
//
// IMPORTANT: hint windows must never use close() with releasedWhenClosed
// (the AppKit default). That over-releases during the next NSApplication
// autorelease-pool drain and crashes with SIGSEGV in releaseUntil.

enum LayoutMotion {

    /// Keeps hint windows alive until their fade finishes (and outlives the
    /// caller's stack frame / animator proxies).
    private final class HintSession {
        let windows: [NSWindow]
        init(_ windows: [NSWindow]) { self.windows = windows }

        func tearDown() {
            for win in windows {
                win.animations.removeAll()
                NSAnimationContext.beginGrouping()
                NSAnimationContext.current.duration = 0
                win.animator().alphaValue = 0
                NSAnimationContext.endGrouping()
                win.orderOut(nil)
                win.contentView = nil
            }
        }
    }

    private static var sessions: [ObjectIdentifier: HintSession] = [:]

    /// Apply many frames at once. Shows a soft destination silhouette for each
    /// target (when animation is enabled), writes every AX frame back-to-back,
    /// then fades the silhouettes together.
    static func apply(
        windows: [AXUIElement],
        frames: [CGRect],
        duration: TimeInterval,
        animated: Bool,
        screenHeight: CGFloat
    ) {
        guard windows.count == frames.count, !windows.isEmpty else { return }
        assert(Thread.isMainThread)

        // 1. Disable enhanced-UI animation on every involved app first so the
        //    size/position/size writes don't race a system animation.
        var preparedPIDs = Set<pid_t>()
        for win in windows {
            var pid: pid_t = 0
            AXUIElementGetPid(win, &pid)
            guard preparedPIDs.insert(pid).inserted else { continue }
            AXWindowOps.disableEnhancedUserInterface(owning: win)
        }

        let destinations = Array(zip(windows, frames))

        var session: HintSession?
        if animated {
            let hints = destinations.map { _, frame in
                makeHint(frame: axToAppKit(frame, screenHeight: screenHeight))
            }
            let s = HintSession(hints)
            sessions[ObjectIdentifier(s)] = s
            session = s

            for hint in hints {
                hint.alphaValue = 0
                hint.orderFront(nil)
            }
            // Instant present — avoid overlapping fade-in + fade-out animations.
            for hint in hints {
                hint.alphaValue = 0.22
            }
        }

        // 2. Commit every frame in one tight burst — no async between windows.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (win, frame) in destinations {
            AXWindowOps.setFrame(win, frame, prepareApp: false)
        }
        CATransaction.commit()

        // 3. Shared fade-out; retain the session until completion.
        guard let session else { return }
        let fade = max(0.18, duration * 0.9)
        let sessionID = ObjectIdentifier(session)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = fade
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
            for hint in session.windows {
                hint.animator().alphaValue = 0
            }
        }, completionHandler: {
            session.tearDown()
            sessions.removeValue(forKey: sessionID)
        })
    }

    // MARK: - Hint windows

    private static func makeHint(frame: CGRect) -> NSWindow {
        let win = NSWindow(
            contentRect: NSRect(origin: .zero, size: frame.size),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        // Critical: we own lifetime via HintSession — never auto-release on close.
        win.isReleasedWhenClosed = false
        win.level = .popUpMenu
        win.backgroundColor = .clear
        win.isOpaque = false
        win.ignoresMouseEvents = true
        win.hasShadow = false
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        win.setFrame(frame, display: false)

        let vfx = NSVisualEffectView(frame: NSRect(origin: .zero, size: frame.size))
        vfx.autoresizingMask = [.width, .height]
        vfx.material = .hudWindow
        vfx.blendingMode = .withinWindow
        vfx.state = .active
        vfx.wantsLayer = true
        vfx.layer?.cornerRadius = 14
        vfx.layer?.masksToBounds = true
        vfx.layer?.borderWidth = 1.25
        vfx.layer?.borderColor = NSColor.white.withAlphaComponent(0.35).cgColor

        let tint = NSView(frame: vfx.bounds)
        tint.autoresizingMask = [.width, .height]
        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.14).cgColor
        vfx.addSubview(tint)

        win.contentView = vfx
        return win
    }

    private static func axToAppKit(_ r: CGRect, screenHeight: CGFloat) -> CGRect {
        CGRect(x: r.origin.x, y: screenHeight - r.origin.y - r.height, width: r.width, height: r.height)
    }
}
