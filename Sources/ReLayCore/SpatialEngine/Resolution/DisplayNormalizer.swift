import CoreGraphics

// Maps per-display CGRect coordinates into a unified spatial coordinate space
// that is stable across mixed-DPI, multi-monitor, and negative-origin setups.
public final class DisplayNormalizer {
    public init() {}

    public func normalize(frame: CGRect, displayID: CGDirectDisplayID) -> SpatialFrame {
        // Unified space already uses AX top-left origin; no per-display offset needed
        // because CGDisplayBounds gives us the global position of each display.
        SpatialFrame(frame)
    }

    public func denormalize(_ frame: SpatialFrame, to displayID: CGDirectDisplayID) -> CGRect {
        frame.cgRect
    }

    // Clamps a spatial frame to the usable bounds of its containing display.
    func clamp(_ frame: SpatialFrame, within map: DisplaySpaceMap) -> SpatialFrame {
        guard let display = map.displayContaining(frame) else { return frame }
        let b = display.bounds
        let clampedX = max(b.x, min(frame.x, b.maxX - frame.width))
        let clampedY = max(b.y, min(frame.y, b.maxY - frame.height))
        return SpatialFrame(x: clampedX, y: clampedY, width: frame.width, height: frame.height)
    }
}
