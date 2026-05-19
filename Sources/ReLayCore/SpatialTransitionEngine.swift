import ApplicationServices
import Cocoa
import Accessibility

// MARK: - Spatial Transition Engine

/// The semantic orchestrator. Sits between GestureEngine (physics) and
/// LayoutOrchestrator (animation). Owns the state machine, drives preview
/// interpolation, and manages multi-window layout operations.
public final class SpatialTransitionEngine {
    public static let shared = SpatialTransitionEngine()

    private let graph    = LayoutTransitionGraph()
    private let store    = WindowStateStore.shared
    private let resolver = LayoutResolver.shared
    private let animator = LayoutOrchestrator.shared

    // MARK: - Session State

    private var sessionWindow:        AXUIElement?
    private var sessionStartFrame:    CGRect = .zero
    private var sessionFingerCount:   Int    = 2
    private var sessionStartLocation: CGPoint = .zero
    private var activeSessionID:      String?

    // MARK: - Multi-window Layout State

    private var tiledEntries: [(window: AXUIElement, original: CGRect)] = []
    private var stageManagerWasEnabled: Bool = false
    private var isInTiledMode: Bool { !tiledEntries.isEmpty }

    private init() {
        AppLogger.log("spatial transition engine initialized", subsystem: "transition")
    }

    // MARK: - Gesture Session Lifecycle

    func beginSession(window: AXUIElement, fingerCount: Int, at location: CGPoint, sessionID: String) {
        self.activeSessionID = sessionID
        AppLogger.log("session begin fingers=\(fingerCount)", sessionID: sessionID, subsystem: "transition")
        sessionWindow        = window
        sessionFingerCount   = fingerCount
        sessionStartLocation = location
        sessionStartFrame    = animator.getWindowFrame(window) ?? .zero

        // Bootstrap the state store if this window hasn't been seen before.
        if store.record(for: window) == nil {
            let screen   = animator.getUsableScreenFrame(for: window)
            let inferred = resolver.inferState(from: sessionStartFrame, on: screen)
            AppLogger.log("bootstrapped window state=\(inferred)", sessionID: sessionID, subsystem: "transition")
            let record   = WindowRecord(
                currentState: inferred,
                floatingFrame: inferred == .floating ? sessionStartFrame : nil
            )
            store.setRecord(record, for: window, sessionID: sessionID)
        }
    }

    /// Called on every scroll delta while a gesture is in progress.
    /// `effectiveX/Y` are axis-locked (one is always 0).
    /// `progress` is in [0, 1] relative to the action threshold.
    func updatePreview(effectiveX: CGFloat, effectiveY: CGFloat, progress: CGFloat, sessionID: String) {
        guard let window = sessionWindow, sessionFingerCount == 2 else {
            if let sid = activeSessionID {
                PreviewManager.shared.dismiss(animated: false, sessionID: sid)
            } else {
                PreviewManager.shared.dismiss(animated: false, sessionID: sessionID)
            }
            return
        }
        guard let direction = GestureDirection(effectiveX: effectiveX, effectiveY: effectiveY) else { return }

        let currentState = store.currentState(for: window) ?? .floating
        guard let nextState = graph.nextState(from: currentState, moving: direction) else {
            PreviewManager.shared.dismiss(animated: false, sessionID: sessionID)
            return
        }

        let screen      = animator.getUsableScreenFrame(for: window)
        let targetFrame = targetFrame(for: nextState, window: window, screen: screen)
        PreviewManager.shared.updateOverlay(
            currentFrame: sessionStartFrame,
            targetFrame:  targetFrame,
            progress:     progress,
            sessionID:    sessionID
        )
    }

    /// Finalizes the gesture. Dispatches to the state machine (2-finger) or a
    /// multi-window operation (3/4-finger).
    func commitSession(effectiveX: CGFloat, effectiveY: CGFloat, fingerCount: Int, at location: CGPoint, sessionID: String) {
        defer { clearSession() }
        guard let window = sessionWindow else { return }
        let direction = GestureDirection(effectiveX: effectiveX, effectiveY: effectiveY)
        AppLogger.log(
            "transition request fingers=\(fingerCount) direction=\(direction.map { String(describing: $0) } ?? "none")",
            sessionID: sessionID,
            subsystem: "transition"
        )

        if fingerCount >= 4 {
            if let dir = direction, dir == .up {
                executeExitLayout(triggerWindow: window, sessionID: sessionID)
            } else {
                executeStageManagerLayout(triggerWindow: window, sessionID: sessionID)
            }
        } else if fingerCount == 3 {
            if let dir = direction, dir == .down, isNearScreenCenter(location) {
                executeThreeColumnLayout(triggerWindow: window, sessionID: sessionID)
            } else {
                executeAutoLayout(triggerWindow: window, sessionID: sessionID)
            }
        } else {
            guard let dir = direction else { cancelSession(sessionID: sessionID); return }
            executeStateTransition(direction: dir, for: window, sessionID: sessionID)
        }
    }

    func cancelSession(sessionID: String) {
        defer { clearSession() }
        AppLogger.log("transition session cancelled", sessionID: sessionID, subsystem: "transition")
        guard let window = sessionWindow, !sessionStartFrame.isEmpty else {
            PreviewManager.shared.dismiss(animated: true, sessionID: sessionID)
            return
        }
        animator.animateWindowFrame(window, to: sessionStartFrame, duration: 0.120, sessionID: sessionID)
        PreviewManager.shared.dismiss(animated: true, sessionID: sessionID)
    }

    // MARK: - 2-finger State Transition

    private func executeStateTransition(direction: GestureDirection, for window: AXUIElement, sessionID: String) {
        guard var record = store.record(for: window) else { return }
        let currentState = record.currentState

        guard let nextState = graph.nextState(from: currentState, moving: direction) else {
            AppLogger.log("no transition available from=\(currentState) direction=\(direction)", sessionID: sessionID, subsystem: "transition")
            // Edge of the graph — snap back
            animator.animateWindowFrame(window, to: sessionStartFrame, duration: 0.120, sessionID: sessionID)
            PreviewManager.shared.dismiss(animated: true, sessionID: sessionID)
            return
        }

        AppLogger.log("state transition request \(currentState) -> \(nextState)", sessionID: sessionID, subsystem: "transition")

        // Capture floating frame before first managed placement
        if currentState == .floating, record.floatingFrame == nil {
            record.floatingFrame = sessionStartFrame
        }

        record.transition(to: nextState)
        store.setRecord(record, for: window, sessionID: sessionID)

        let screen      = animator.getUsableScreenFrame(for: window)
        AppLogger.log("layout resolution request state=\(nextState)", sessionID: sessionID, subsystem: "transition")
        let targetFrame = targetFrame(for: nextState, window: window, screen: screen)

        PreviewManager.shared.commitOverlay(finalFrame: targetFrame, sessionID: sessionID)
        animator.animateWindowFrame(window, to: targetFrame, sessionID: sessionID)
    }

    // MARK: - Multi-window Operations

    private func executeAutoLayout(triggerWindow: AXUIElement, sessionID: String) {
        let screen = animator.getUsableScreenFrame(for: triggerWindow)
        AppLogger.log("layout resolution request state=fullscreen auto-layout", sessionID: sessionID, subsystem: "transition")
        let target = resolver.frame(for: .fullscreen, on: screen)

        if var record = store.record(for: triggerWindow) {
            if record.floatingFrame == nil { record.floatingFrame = sessionStartFrame }
            record.transition(to: .fullscreen)
            store.setRecord(record, for: triggerWindow, sessionID: sessionID)
        }

        PreviewManager.shared.commitOverlay(finalFrame: target, sessionID: sessionID)
        animator.animateWindowFrame(triggerWindow, to: target, sessionID: sessionID)
    }

    private func executeThreeColumnLayout(triggerWindow: AXUIElement, sessionID: String) {
        AppLogger.log("transition request three-column layout", sessionID: sessionID, subsystem: "transition")
        let screen  = animator.getUsableScreenFrame(for: triggerWindow)
        var windows = animator.getAllVisibleWindows()
        guard windows.count >= 3 else { executeAutoLayout(triggerWindow: triggerWindow, sessionID: sessionID); return }

        // Trigger window always takes column 0
        windows.removeAll { CFEqual($0, triggerWindow) }
        windows.insert(triggerWindow, at: 0)
        let selected = Array(windows.prefix(3))

        tiledEntries = selected.compactMap { w in
            guard let f = animator.getWindowFrame(w) else { return nil }
            return (window: w, original: f)
        }
        stageManagerWasEnabled = animator.isStageManagerEnabled()
        if stageManagerWasEnabled { animator.setStageManager(false) }

        animator.tileWindows(selected, in: screen, columns: 3, gap: 2, sessionID: sessionID)
        PreviewManager.shared.dismiss(animated: false, sessionID: sessionID)
    }

    private func executeStageManagerLayout(triggerWindow: AXUIElement, sessionID: String) {
        AppLogger.log("transition request stage-manager layout", sessionID: sessionID, subsystem: "transition")
        let screen  = animator.getUsableScreenFrame(for: triggerWindow)
        let windows = animator.getAllVisibleWindows()
        guard !windows.isEmpty else { return }

        tiledEntries = windows.compactMap { w in
            guard let f = animator.getWindowFrame(w) else { return nil }
            return (window: w, original: f)
        }
        stageManagerWasEnabled = animator.isStageManagerEnabled()
        if stageManagerWasEnabled { animator.setStageManager(false) }

        animator.tileWindows(windows, in: screen, columns: nil, gap: 2, sessionID: sessionID)
        PreviewManager.shared.dismiss(animated: false, sessionID: sessionID)
    }

    private func executeExitLayout(triggerWindow: AXUIElement, sessionID: String) {
        AppLogger.log("transition request exit-layout", sessionID: sessionID, subsystem: "transition")
        // Exit native full screen first if applicable
        var fsRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(triggerWindow, "AXFullScreen" as CFString, &fsRef) == .success,
           let isFS = fsRef as? Bool, isFS {
            AXUIElementSetAttributeValue(triggerWindow, "AXFullScreen" as CFString, false as CFTypeRef)
            store.updateState(.floating, for: triggerWindow, sessionID: sessionID)
            return
        }

        // Restore tiled layout
        if isInTiledMode {
            for entry in tiledEntries {
                animator.animateWindowFrame(entry.window, to: entry.original, sessionID: sessionID)
            }
            tiledEntries = []
            if stageManagerWasEnabled { animator.setStageManager(true) }
            stageManagerWasEnabled = false
        }

        PreviewManager.shared.dismiss(animated: false, sessionID: sessionID)
    }

    // MARK: - Helpers

    /// Resolves the target CGRect for a state, substituting the saved floating
    /// frame when the next state is `.floating`.
    private func targetFrame(for state: WindowLayoutState, window: AXUIElement, screen: CGRect) -> CGRect {
        if state == .floating {
            return store.record(for: window)?.floatingFrame ?? sessionStartFrame
        }
        return resolver.frame(for: state, on: screen)
    }

    private func isNearScreenCenter(_ location: CGPoint) -> Bool {
        let screen = NSScreen.screens.first(where: { $0.frame.contains(location) }) ?? NSScreen.main
        guard let screen = screen else { return false }
        let center = CGPoint(x: screen.frame.midX, y: screen.frame.midY)
        return abs(location.x - center.x) <= 160 && abs(location.y - center.y) <= 160
    }

    private func clearSession() {
        if let sessionID = activeSessionID {
            AppLogger.log("transition session cleared", sessionID: sessionID, subsystem: "transition")
        } else {
            AppLogger.log("transition session cleared", subsystem: "transition")
        }
        sessionWindow        = nil
        sessionStartFrame    = .zero
        sessionFingerCount   = 2
        sessionStartLocation = .zero
        activeSessionID      = nil
    }
}
