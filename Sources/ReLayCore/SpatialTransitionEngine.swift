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
    private var sessionScreenFrame:   CGRect = .zero

    // MARK: - Multi-window Layout State

    private var tiledEntries: [(window: AXUIElement, original: CGRect)] = []
    private var stageManagerWasEnabled: Bool = false
    private var isInTiledMode: Bool { !tiledEntries.isEmpty }
    
    private var lastExposeUndoFrames: [WindowID: CGRect]?
    private var lastExposeState: (template: LayoutTemplate, windows: [AXUIElement], screenFrame: CGRect)?

    public var canUndo: Bool { lastExposeUndoFrames != nil }
    public var canShuffle: Bool { (lastExposeState?.windows.count ?? 0) >= 2 }
    
    private init() {
        AppLogger.log("spatial transition engine initialized", subsystem: "transition")
    }

    // MARK: - Gesture Session Lifecycle

    func beginSession(window: AXUIElement, fingerCount: Int, at location: CGPoint) {
        AppLogger.log("session begin fingers=\(fingerCount)", subsystem: "transition")
        sessionWindow        = window
        sessionFingerCount   = fingerCount
        sessionStartLocation = location
        sessionStartFrame    = animator.getWindowFrame(window) ?? .zero
        sessionScreenFrame   = animator.getUsableScreenFrame(for: window, at: location)

        // Bootstrap the state store if this window hasn't been seen before.
        if store.record(for: window) == nil {
            let inferred = resolver.inferState(from: sessionStartFrame, on: sessionScreenFrame)
            AppLogger.log("bootstrapped window state=\(inferred)", subsystem: "transition")
            let record   = WindowRecord(
                currentState: inferred,
                floatingFrame: inferred == .floating ? sessionStartFrame : nil
            )
            store.setRecord(record, for: window)
        }
    }

    /// Called on every scroll delta while a gesture is in progress.
    /// `effectiveX/Y` are axis-locked (one is always 0).
    /// `progress` is in [0, 1] relative to the action threshold.
    func updatePreview(effectiveX: CGFloat, effectiveY: CGFloat, progress: CGFloat) {
        guard let window = sessionWindow, sessionFingerCount == 2 else {
            PreviewManager.shared.dismiss(animated: false)
            return
        }
        guard let direction = GestureDirection(effectiveX: effectiveX, effectiveY: effectiveY) else { return }

        let currentState = store.currentState(for: window) ?? .floating
        guard let nextState = graph.nextState(from: currentState, moving: direction) else {
            PreviewManager.shared.dismiss(animated: false)
            return
        }

        let targetFrame = targetFrame(for: nextState, window: window, screen: sessionScreenFrame)
        PreviewManager.shared.updateOverlay(
            currentFrame: sessionStartFrame,
            targetFrame:  targetFrame,
            progress:     progress
        )
    }

    /// Finalizes the gesture. Dispatches to the state machine (2-finger) or a
    /// multi-window operation (3/4-finger).
    func commitSession(effectiveX: CGFloat, effectiveY: CGFloat, fingerCount: Int, at location: CGPoint) {
        defer { clearSession() }
        guard let window = sessionWindow else { return }
        let direction = GestureDirection(effectiveX: effectiveX, effectiveY: effectiveY)
        AppLogger.log(
            "transition request fingers=\(fingerCount) direction=\(direction.map { String(describing: $0) } ?? "none")",
            subsystem: "transition"
        )

        if fingerCount >= 4 {
            if let dir = direction, dir == .up {
                executeExitLayout(triggerWindow: window)
            } else {
                executeStageManagerLayout(triggerWindow: window)
            }
        } else if fingerCount == 3 {
            if let dir = direction, dir == .down {
                executeLayoutExpose(triggerWindow: window)
            } else {
                executeAutoLayout(triggerWindow: window)
            }
        } else {
            guard let dir = direction else { cancelSession(); return }
            executeStateTransition(direction: dir, for: window)
        }
    }

    func cancelSession() {
        defer { clearSession() }
        AppLogger.log("transition session cancelled", subsystem: "transition")
        guard let window = sessionWindow, !sessionStartFrame.isEmpty else {
            PreviewManager.shared.dismiss(animated: true)
            return
        }
        animator.animateWindowFrame(window, to: sessionStartFrame, duration: 0.120)
        PreviewManager.shared.dismiss(animated: true)
    }

    // MARK: - 2-finger State Transition

    private func executeStateTransition(direction: GestureDirection, for window: AXUIElement) {
        guard var record = store.record(for: window) else { return }
        let currentState = record.currentState

        guard let nextState = graph.nextState(from: currentState, moving: direction) else {
            AppLogger.log("no transition available from=\(currentState) direction=\(direction)", subsystem: "transition")
            // Edge of the graph — snap back
            animator.animateWindowFrame(window, to: sessionStartFrame, duration: 0.120)
            PreviewManager.shared.dismiss(animated: true)
            return
        }

        AppLogger.log("state transition request \(currentState) -> \(nextState)", subsystem: "transition")

        // Capture floating frame before first managed placement
        if currentState == .floating, record.floatingFrame == nil {
            record.floatingFrame = sessionStartFrame
        }

        record.transition(to: nextState)
        store.setRecord(record, for: window)

        AppLogger.log("layout resolution request state=\(nextState)", subsystem: "transition")
        let targetFrame = targetFrame(for: nextState, window: window, screen: sessionScreenFrame)

        PreviewManager.shared.commitOverlay(finalFrame: targetFrame)
        animator.animateWindowFrame(window, to: targetFrame)
    }

    // MARK: - Multi-window Operations

    private func executeLayoutExpose(triggerWindow: AXUIElement) {
        AppLogger.log("transition request layout-expose", subsystem: "transition")
        PreviewManager.shared.dismiss(animated: false)
        LayoutExposeController.shared.present(triggerWindow: triggerWindow)
    }
    
    func registerExposeState(template: LayoutTemplate, windows: [AXUIElement], screenFrame: CGRect) {
        lastExposeState = (template, windows, screenFrame)
    }

    public func shuffleExposeLayout() {
        guard let state = lastExposeState, state.windows.count >= 2 else { return }
        let template = state.template
        var windows = state.windows
        let screenFrame = state.screenFrame
        AppLogger.log("shuffling expose layout windows=\(windows.count)", subsystem: "transition")

        var origFrames: [AXUIElement: CGRect] = [:]
        for w in windows {
            if let f = animator.getWindowFrame(w) { origFrames[w] = f }
        }
        registerExposeUndo(frames: origFrames)

        let last = windows.removeLast()
        windows.insert(last, at: 0)

        for (idx, slot) in template.slots.enumerated() where idx < windows.count {
            let target = template.frame(for: slot, in: screenFrame)
            animator.animateWindowFrame(windows[idx], to: target)
        }

        lastExposeState = (template, windows, screenFrame)
    }

    func registerExposeUndo(frames: [AXUIElement: CGRect]) {
        var undoMap: [WindowID: CGRect] = [:]
        for (window, frame) in frames {
            undoMap[WindowID(element: window)] = frame
        }
        lastExposeUndoFrames = undoMap
    }

    public func performExposeUndo() {
        guard let frames = lastExposeUndoFrames else { 
            AppLogger.log("undo requested but no frames stored", subsystem: "transition")
            return 
        }
        AppLogger.log("performing undo for \(frames.count) windows", subsystem: "transition")
        for (id, frame) in frames {
            animator.animateWindowFrame(id.element, to: frame)
        }
        lastExposeUndoFrames = nil
    }

    private func executeAutoLayout(triggerWindow: AXUIElement) {
        let screen = sessionScreenFrame != .zero ? sessionScreenFrame : animator.getUsableScreenFrame(for: triggerWindow)
        AppLogger.log("layout resolution request state=fullscreen auto-layout", subsystem: "transition")
        let target = resolver.frame(for: .fullscreen, on: screen)

        if var record = store.record(for: triggerWindow) {
            if record.floatingFrame == nil { record.floatingFrame = sessionStartFrame }
            record.transition(to: .fullscreen)
            store.setRecord(record, for: triggerWindow)
        }

        PreviewManager.shared.commitOverlay(finalFrame: target)
        animator.animateWindowFrame(triggerWindow, to: target)
    }

    private func executeThreeColumnLayout(triggerWindow: AXUIElement) {
        AppLogger.log("transition request three-column layout", subsystem: "transition")
        let screen = sessionScreenFrame != .zero ? sessionScreenFrame : animator.getUsableScreenFrame(for: triggerWindow)
        var windows = animator.getAllVisibleWindows()
        guard windows.count >= 3 else { executeAutoLayout(triggerWindow: triggerWindow); return }

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

        animator.tileWindows(selected, in: screen, columns: 3, gap: 2)
        PreviewManager.shared.dismiss(animated: false)
    }

    private func executeStageManagerLayout(triggerWindow: AXUIElement) {
        AppLogger.log("transition request stage-manager layout", subsystem: "transition")
        let screen = sessionScreenFrame != .zero ? sessionScreenFrame : animator.getUsableScreenFrame(for: triggerWindow)
        let windows = animator.getAllVisibleWindows()
        guard !windows.isEmpty else { return }

        tiledEntries = windows.compactMap { w in
            guard let f = animator.getWindowFrame(w) else { return nil }
            return (window: w, original: f)
        }
        stageManagerWasEnabled = animator.isStageManagerEnabled()
        if stageManagerWasEnabled { animator.setStageManager(false) }

        animator.tileWindows(windows, in: screen, columns: nil, gap: 2)
        PreviewManager.shared.dismiss(animated: false)
    }

    private func executeExitLayout(triggerWindow: AXUIElement) {
        AppLogger.log("transition request exit-layout", subsystem: "transition")
        // Exit native full screen first if applicable
        var fsRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(triggerWindow, "AXFullScreen" as CFString, &fsRef) == .success,
           let isFS = fsRef as? Bool, isFS {
            AXUIElementSetAttributeValue(triggerWindow, "AXFullScreen" as CFString, false as CFTypeRef)
            store.updateState(.floating, for: triggerWindow)
            return
        }

        // Restore tiled layout
        if isInTiledMode {
            for entry in tiledEntries {
                animator.animateWindowFrame(entry.window, to: entry.original)
            }
            tiledEntries = []
            if stageManagerWasEnabled { animator.setStageManager(true) }
            stageManagerWasEnabled = false
        }

        PreviewManager.shared.dismiss(animated: false)
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
        AppLogger.log("transition session cleared", subsystem: "transition")
        sessionWindow        = nil
        sessionStartFrame    = .zero
        sessionFingerCount   = 2
        sessionStartLocation = .zero
    }
}
