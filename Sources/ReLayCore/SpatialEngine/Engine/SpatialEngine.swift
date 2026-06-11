import AppKit
import ApplicationServices
import CoreGraphics
import Accessibility
import Foundation

// Main orchestrator for the spatial layer. Sits between ActionDispatcher and the window layer.
// All state is indexed by AXUIElement identity (ObjectIdentifier) for O(1) lookup.
public final class SpatialEngine {
    public static let shared = SpatialEngine()

    private let layoutEngine = LayoutEngine()
    private let bridge = SpatialToWindowBridge()
    private let normalizer = DisplayNormalizer()

    // Keyed by window identity so we don't hold strong AXUIElement references in a dict.
    private var frames: [(window: AXUIElement, frame: SpatialFrame)] = []

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
        frames = zip(frames, updated).map { pair, newFrame in (window: pair.window, frame: newFrame) }
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

    // MARK: - Gesture Session
    //
    // `frames` holds AXUIElements resolved once via capture()/resync(). During an
    // active gesture, applyGestureDelta writes directly through
    // LayoutOrchestrator.setWindowFrame — write-only, no AXUIElementCopyAttributeValue
    // reads and no per-event animation timers — so continuous gesture deltas never
    // re-resolve or re-read AX state. A short idle timeout ends the session
    // automatically once deltas stop arriving.
    private var gestureActive = false
    private var staleFrameIndices: Set<Int> = []
    private var gestureIdleWork: DispatchWorkItem?
    private let gestureIdleTimeout: TimeInterval = 0.15

    public var hasActiveGestureSession: Bool { gestureActive }

    /// Starts a gesture session, resolving AXUIElements via resync() if `frames`
    /// hasn't been captured yet. Idempotent — a no-op if already active.
    public func beginGestureSession() {
        guard !gestureActive else { return }
        if frames.isEmpty { resync() }
        gestureActive = true
        staleFrameIndices.removeAll()
        AppLogger.log("spatial engine: gesture session started count=\(frames.count)", subsystem: "spatial")
    }

    /// Applies `delta` to every captured frame via write-only AX calls. If a write
    /// fails (e.g. the window closed mid-gesture), that frame is marked stale and
    /// every frame is re-resolved via resync() exactly once, on the next call —
    /// never retried within the same call.
    @discardableResult
    public func applyGestureDelta(_ delta: CGPoint) -> Bool {
        guard gestureActive, !frames.isEmpty else { return false }

        if !staleFrameIndices.isEmpty {
            resync()
            staleFrameIndices.removeAll()
        }

        let updated = layoutEngine.applyTransform(frames: frames.map(\.frame), delta: delta)
        for (i, frame) in updated.enumerated() {
            frames[i].frame = frame
            if !LayoutOrchestrator.shared.setWindowFrame(frames[i].window, frame: frame.cgRect, source: "gesture") {
                staleFrameIndices.insert(i)
            }
        }

        scheduleGestureIdleEnd()
        return staleFrameIndices.isEmpty
    }

    /// Ends the current gesture session. Safe to call even if no session is active.
    public func endGestureSession() {
        guard gestureActive else { return }
        gestureActive = false
        gestureIdleWork?.cancel()
        gestureIdleWork = nil
        AppLogger.log("spatial engine: gesture session ended", subsystem: "spatial")
    }

    private func scheduleGestureIdleEnd() {
        gestureIdleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.endGestureSession() }
        gestureIdleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + gestureIdleTimeout, execute: work)
    }

    // MARK: - Private

    private func primaryDisplayID() -> CGDirectDisplayID {
        CGMainDisplayID()
    }
}
