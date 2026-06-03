import CoreGraphics

// Converts between macOS AX coordinate space (top-left origin, physical pixels)
// and the SpatialEngine's unified coordinate space.
struct CoordinateResolver {
    let map: DisplaySpaceMap

    // AX → spatial (currently 1:1 since both share top-left origin)
    func toSpatial(_ rect: CGRect) -> SpatialFrame {
        SpatialFrame(rect)
    }

    // Spatial → AX
    func toAX(_ frame: SpatialFrame) -> CGRect {
        frame.cgRect
    }

    // Re-anchor a frame to the nearest display if it has drifted off-screen.
    func reanchor(_ frame: SpatialFrame) -> SpatialFrame {
        guard let display = map.displayContaining(frame) else {
            // Frame is completely off all displays; move to primary display origin.
            guard let primary = map.displays.first else { return frame }
            return SpatialFrame(x: primary.bounds.x + 20, y: primary.bounds.y + 20,
                                width: frame.width, height: frame.height)
        }
        let b = display.bounds
        let x = max(b.x, min(frame.x, b.maxX - frame.width))
        let y = max(b.y, min(frame.y, b.maxY - frame.height))
        return SpatialFrame(x: x, y: y, width: frame.width, height: frame.height)
    }
}
