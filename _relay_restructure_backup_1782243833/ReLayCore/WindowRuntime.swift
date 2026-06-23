import Cocoa
import ApplicationServices

// MARK: - Window Runtime
// Orchestrator: receive intent → resolve window → ask policy → call AX.
// No AX logic. No heuristics. No persistence. No singleton.

public final class WindowRuntime: EventTapCaptureDelegate {

    private let capture: EventTapCapture
    private var state:          State  = State()
    private var activeBundleID: String = ""
    private let config:         Config

    private var previewOverlay:    NSWindow?
    private var snapTargetOverlay: NSWindow?

    public init(config: Config = .load()) {
        self.config  = config
        self.capture = EventTapCapture()
        setupPreview()
        capture.delegate = self
    }

    public func start() throws { try capture.start() }
    public func stop()        { capture.stop() }

    // MARK: - Capture → Reduce → Policy → Execute

    func didReceive(_ intent: WindowIntent) {
        let window: AXUIElement? = (intent.phase == .began) ? AXWindowOps.frontmost() : state.activeWindow
        if intent.phase == .began {
            activeBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        }
        let screen = window.flatMap { AXWindowOps.frame($0) }.map { Self.usableScreen(containing: $0) } ?? .zero
        let input  = Input(dx: intent.dx, dy: intent.dy,
                           phase: intent.phase, window: window, screenFrame: screen)
        let prev = state
        state    = reduce(state, input)
        apply(prev: prev, curr: state)
    }

    // MARK: - Apply

    private func apply(prev: State, curr: State) {
        guard let window = curr.activeWindow else {
            AppLogger.log("apply: no active window", subsystem: "runtime")
            return
        }

        AppLogger.log("apply: committed=\(curr.hasCommitted) progress=\(curr.progress) bundleID=\(activeBundleID)", subsystem: "runtime")

        if prev.activeWindow == nil && curr.activeWindow != nil {
            state.startFrame = AXWindowOps.frame(window) ?? .zero
            AppLogger.log("apply: captured startFrame=\(state.startFrame)", subsystem: "runtime")
        }

        if curr.hasCommitted && !prev.hasCommitted {
            AppLogger.log("apply: COMMIT transition, targetFrame=\(curr.targetFrame)", subsystem: "runtime")
            commitPreview(to: curr.targetFrame)
            let policy = WindowMutabilityPolicy.decision(for: activeBundleID)
            AppLogger.log("apply: policy decision=\(policy) for \(activeBundleID)", subsystem: "runtime")
            if policy == .allow {
                AppLogger.log("apply: calling setFrame with \(curr.targetFrame)", subsystem: "runtime")
                AXWindowOps.setFrame(window, curr.targetFrame)
            } else {
                AppLogger.log("apply: policy blocked frame move", subsystem: "runtime")
            }
        } else if !curr.hasCommitted && curr.progress == 0
                    && (prev.accumulatedX != 0 || prev.accumulatedY != 0) {
            AppLogger.log("apply: CANCEL, resetting to startFrame=\(state.startFrame)", subsystem: "runtime")
            if !state.startFrame.isEmpty && WindowMutabilityPolicy.decision(for: activeBundleID) == .allow {
                AXWindowOps.setFrame(window, state.startFrame)
            }
            dismissPreview(animated: true)
        } else if curr.progress > 0 {
            AppLogger.log("apply: preview update progress=\(curr.progress)", subsystem: "runtime")
            updatePreview(from: state.startFrame, to: curr.targetFrame, progress: curr.progress)
        }
    }

    // MARK: - Screen resolution (NSScreen — not AX)
    // Static so LayoutLibraryController can call the single canonical implementation.

    static func usableScreen(containing frame: CGRect) -> CGRect {
        guard let primary = NSScreen.screens.first else { return .zero }
        let toAX: (NSScreen) -> CGRect = { s in
            CGRect(x: s.frame.minX, y: primary.frame.height - s.frame.minY - s.frame.height,
                   width: s.frame.width, height: s.frame.height)
        }
        let target = NSScreen.screens.max(by: {
            toAX($0).intersection(frame).area < toAX($1).intersection(frame).area
        }) ?? (NSScreen.main ?? primary)
        let vf = target.visibleFrame
        return CGRect(x: vf.minX, y: primary.frame.height - vf.minY - vf.height,
                      width: vf.width, height: vf.height)
    }

    // MARK: - Preview (AppKit only — no AX)

    private func setupPreview() {
        previewOverlay    = makeOverlay(material: .selection,             borderOpacity: 0.3)
        snapTargetOverlay = makeOverlay(material: .underWindowBackground, borderOpacity: 0.1)
    }

    private func makeOverlay(material: NSVisualEffectView.Material, borderOpacity: CGFloat) -> NSWindow {
        let win = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        win.level = .popUpMenu; win.backgroundColor = .clear
        win.isOpaque = false; win.ignoresMouseEvents = true; win.hasShadow = false
        let vfx = NSVisualEffectView()
        vfx.material = material; vfx.blendingMode = .behindWindow; vfx.state = .active
        vfx.wantsLayer = true
        vfx.layer?.cornerRadius = 12; vfx.layer?.borderWidth = 1.5
        vfx.layer?.borderColor = NSColor.white.withAlphaComponent(borderOpacity).cgColor
        win.contentView = vfx
        return win
    }

    private func updatePreview(from current: CGRect, to target: CGRect, progress: CGFloat) {
        guard let overlay = previewOverlay, let snap = snapTargetOverlay else { return }
        let cur = axToAppKit(current), tgt = axToAppKit(target)
        if !snap.isVisible {
            snap.setFrame(tgt, display: true); snap.alphaValue = 0; snap.orderFront(nil)
            NSAnimationContext.runAnimationGroup { $0.duration = 0.15; snap.animator().alphaValue = 0.15 }
        } else { snap.animator().setFrame(tgt, display: true) }
        let active = CGRect(
            x: cur.minX + (tgt.minX - cur.minX) * progress,
            y: cur.minY + (tgt.minY - cur.minY) * progress,
            width:  cur.width  + (tgt.width  - cur.width)  * progress,
            height: cur.height + (tgt.height - cur.height) * progress
        )
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.05
            overlay.animator().setFrame(active, display: true)
            overlay.animator().alphaValue = min(0.35, progress * 0.6)
        }
        if !overlay.isVisible { overlay.orderFront(nil) }
    }

    private func commitPreview(to frame: CGRect) {
        guard let overlay = previewOverlay, overlay.isVisible else { return }
        snapTargetOverlay?.alphaValue = 0; snapTargetOverlay?.orderOut(nil)
        overlay.setFrame(axToAppKit(frame), display: true)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.220
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
            overlay.animator().alphaValue = 0
        }, completionHandler: { overlay.orderOut(nil) })
    }

    private func dismissPreview(animated: Bool) {
        for win in [previewOverlay, snapTargetOverlay].compactMap({ $0 }) {
            guard win.isVisible else { continue }
            if animated {
                NSAnimationContext.runAnimationGroup(
                    { $0.duration = 0.120; win.animator().alphaValue = 0 },
                    completionHandler: { win.orderOut(nil) })
            } else { win.alphaValue = 0; win.orderOut(nil) }
        }
    }

    // Coordinate flip: AX origin (top-left) → AppKit origin (bottom-left)
    private func axToAppKit(_ r: CGRect) -> CGRect {
        let h = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: r.origin.x, y: h - r.origin.y - r.height, width: r.width, height: r.height)
    }
}

private extension CGRect {
    var area: CGFloat { width * height }
}
// NOTE: WindowLayoutState merged into WindowRuntime
import CoreGraphics

// MARK: - Gesture Direction

enum GestureDirection: Hashable {
    case left, right, up, down

    init?(effectiveX: CGFloat, effectiveY: CGFloat) {
        guard effectiveX != 0 || effectiveY != 0 else { return nil }
        if abs(effectiveX) > abs(effectiveY) {
            self = effectiveX > 0 ? .right : .left
        } else {
            // Natural scrolling: positive Y = swipe up
            self = effectiveY > 0 ? .up : .down
        }
    }
}

// MARK: - Semantic Layout State

enum WindowLayoutState: Hashable, CaseIterable {
    // Unmanaged — frame does not match any known state
    case floating

    // Full-screen states
    case fullscreen     // 100% width, 100% height
    case center         // ~72% width, centered, full height

    // Left column
    case leftHalf           // 50% left
    case leftThird          // 33% left, full height
    case leftTopSixth       // 33% left, top 50%
    case leftBottomSixth    // 33% left, bottom 50%

    // Right column
    case rightHalf          // 50% right
    case rightThird         // 33% right, full height
    case rightTopSixth      // 33% right, top 50%
    case rightBottomSixth   // 33% right, bottom 50%
}

// MARK: - Transition Graph

private struct TransitionKey: Hashable {
    let state: WindowLayoutState
    let direction: GestureDirection
}

/// Declarative lookup table: (WindowLayoutState × GestureDirection) → WindowLayoutState.
/// All entries cover 2-finger gestures only. Multi-finger operations are
/// handled as special cases in the reducer.
class LayoutTransitionGraph {

    private var table: [TransitionKey: WindowLayoutState] = [:]

    init() { buildTable() }

    func nextState(from state: WindowLayoutState, moving direction: GestureDirection) -> WindowLayoutState? {
        return table[TransitionKey(state: state, direction: direction)]
    }

    private func buildTable() {
        func add(_ from: WindowLayoutState, _ dir: GestureDirection, _ to: WindowLayoutState) {
            table[TransitionKey(state: from, direction: dir)] = to
        }

        // MARK: Horizontal — navigate columns
        for state in [WindowLayoutState.floating, .fullscreen] {
            add(state, .left,  .leftHalf)
            add(state, .right, .rightHalf)
        }
        // Center navigates out to halves in either mode
        add(.center, .left,  .leftHalf)
        add(.center, .right, .rightHalf)
        // Half → third (push further) or cross-side jump (pull back)
        add(.leftHalf,  .left,  .leftThird)
        add(.leftHalf,  .right, .rightHalf)
        add(.rightHalf, .right, .rightThird)
        add(.rightHalf, .left,  .leftHalf)
        // Third → half (pull back; edge resist in other direction)
        add(.leftThird,  .right, .leftHalf)
        add(.rightThird, .left,  .rightHalf)
        // Cross-column: jump sixths across the screen
        add(.leftTopSixth,    .right, .rightTopSixth)
        add(.leftBottomSixth, .right, .rightBottomSixth)
        add(.rightTopSixth,   .left,  .leftTopSixth)
        add(.rightBottomSixth,.left,  .leftBottomSixth)

        // Vertical gestures (up/down) are resolved directly in the reducer.
    }
}
