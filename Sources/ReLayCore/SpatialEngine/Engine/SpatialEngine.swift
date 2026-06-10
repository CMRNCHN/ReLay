import CoreGraphics
import Accessibility

// Main orchestrator for the spatial layer. Sits between ActionDispatcher and the window layer.
// All state is indexed by AXUIElement identity (ObjectIdentifier) for O(1) lookup.
public final class SpatialEngine {
    public static let shared = SpatialEngine()

    private let layoutEngine = LayoutEngine()
    private let bridge = SpatialToWindowBridge()
    private let normalizer = DisplayNormalizer()
    private let mover = WindowMover()

    // Keyed by window identity so we don't hold strong AXUIElement references in a dict.
    private var frames: [(window: AXUIElement, frame: SpatialFrame)] = []

    // MARK: - Gesture Session
    //
    // AXUIElement resolution happens once per gesture (beginGestureSession), not
    // per frame. The 60fps lerp drain in SpatialStateCore calls applyGestureDelta,
    // which only performs write-only AX calls (setWindowFrame) against the cached
    // elements — no AXUIElementCopyAttributeValue lookups in the hot loop.
    private struct GestureTarget {
        var window: AXUIElement
        var frame: CGRect
        var stale: Bool = false
        var reresolveAttempted: Bool = false
    }
    private var gestureTargets: [String: GestureTarget] = [:]

    public var hasActiveGestureSession: Bool { !gestureTargets.isEmpty }

    private init() {}

    // MARK: - Public API

    // Capture the current spatial state of a set of windows.
    public func capture(windows: [(AXUIElement, CGRect)]) {
        frames = windows.map { (window, rect) in
            (window: window, frame: normalizer.normalize(frame: rect, displayID: primaryDisplayID()))
        }
        AppLogger.log("spatial engine: captured \(frames.count) windows", subsystem: "spatial")
    }

    // Translate all captured windows by delta, resolve collisions, stabilize, then apply.
    public func moveWorkspace(delta: CGPoint) {
        guard !frames.isEmpty else { return }
        let updated = layoutEngine.applyTransform(
            frames: frames.map(\.frame),
            delta: delta
        )
        frames = zip(frames, updated).map { ($0.0.window, $1) }
        bridge.apply(frames)
        AppLogger.log("spatial engine: moveWorkspace delta=\(delta) windows=\(frames.count)", subsystem: "spatial")
    }

    // Move a single window in spatial space (used by intent dispatcher).
    public func moveWindow(_ window: AXUIElement, delta: CGPoint) {
        guard let idx = frames.firstIndex(where: { CFEqual($0.window, window) }) else {
            // Window not yet captured; read its current frame and adopt it.
            if let rect = LayoutOrchestrator.shared.getWindowFrame(window) {
                let spatial = normalizer.normalize(frame: rect, displayID: primaryDisplayID())
                let updated = layoutEngine.applyTransform(frame: spatial, delta: delta)
                let map = DisplaySpaceMap.current()
                let resolver = CoordinateResolver(map: map)
                let reanchored = resolver.reanchor(updated)
                bridge.apply(frame: reanchored, to: window)
            }
            return
        }
        let updated = layoutEngine.applyTransform(frame: frames[idx].frame, delta: delta)
        let map = DisplaySpaceMap.current()
        let resolver = CoordinateResolver(map: map)
        let reanchored = resolver.reanchor(updated)
        frames[idx].frame = reanchored
        bridge.apply(frame: reanchored, to: window)
    }

    // Re-read all window positions from AX and refresh internal state.
    public func resync() {
        let windows = LayoutOrchestrator.shared.getAllVisibleWindows()
        let pairs: [(AXUIElement, CGRect)] = windows.compactMap { w in
            guard let rect = LayoutOrchestrator.shared.getWindowFrame(w) else { return nil }
            return (w, rect)
        }
        capture(windows: pairs)
        AppLogger.log("spatial engine: resynced \(pairs.count) windows", subsystem: "spatial")
    }

    // MARK: - Gesture Session API

    /// Resolve AXUIElements for every window once, at gesture start.
    /// A no-op if a session is already active (idempotent across repeated
    /// applyWorkspaceMove calls within the same gesture).
    public func beginGestureSession(windows: [WindowModel]) {
        guard gestureTargets.isEmpty else { return }
        for model in windows {
            guard let ax = mover.findAXWindow(for: model) else { continue }
            gestureTargets[model.id] = GestureTarget(window: ax, frame: model.frame)
        }
        AppLogger.log(
            "spatial engine: gesture session started resolved=\(gestureTargets.count)/\(windows.count)",
            subsystem: "spatial"
        )
    }

    /// Apply `delta` to every resolved window via write-only AX calls.
    /// Returns updated WindowModels (new frames) for the caller to sync into state.
    /// If a write fails (window closed mid-gesture), the target is marked stale and
    /// re-resolved exactly once on the next call — never retried within a frame.
    @discardableResult
    public func applyGestureDelta(_ delta: CGPoint, to windows: [WindowModel]) -> [WindowModel] {
        windows.map { model -> WindowModel in
            var model = model
            guard var target = gestureTargets[model.id] else { return model }

            if target.stale && !target.reresolveAttempted {
                target.reresolveAttempted = true
                if let ax = mover.findAXWindow(for: model) {
                    target.window = ax
                    target.stale  = false
                }
            }

            target.frame = target.frame.offsetBy(dx: delta.x, dy: delta.y)
            model.frame  = target.frame

            if !target.stale {
                let success = LayoutOrchestrator.shared.setWindowFrame(target.window, frame: target.frame, source: "gesture")
                target.stale = !success
            }

            gestureTargets[model.id] = target
            return model
        }
    }

    /// Clear cached AX references. Call once the gesture has settled.
    public func endGestureSession() {
        guard !gestureTargets.isEmpty else { return }
        AppLogger.log("spatial engine: gesture session ended count=\(gestureTargets.count)", subsystem: "spatial")
        gestureTargets.removeAll()
    }

    // MARK: - Private

    private func primaryDisplayID() -> CGDirectDisplayID {
        CGMainDisplayID()
    }
}
