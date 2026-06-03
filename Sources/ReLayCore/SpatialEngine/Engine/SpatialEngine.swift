import CoreGraphics
import Accessibility

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

    // MARK: - Private

    private func primaryDisplayID() -> CGDirectDisplayID {
        CGMainDisplayID()
    }
}
