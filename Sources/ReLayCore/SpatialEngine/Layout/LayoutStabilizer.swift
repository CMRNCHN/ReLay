import CoreGraphics

// Absorbs accumulated floating-point drift from repeated delta applications.
// Snaps frames to integer pixel boundaries and suppresses sub-pixel jitter.
struct LayoutStabilizer {
    private static let driftThreshold: CGFloat = 0.5

    // Round sub-pixel positions to the nearest physical pixel.
    func stabilize(_ frames: [SpatialFrame]) -> [SpatialFrame] {
        frames.map { f in
            SpatialFrame(
                x: snap(f.x),
                y: snap(f.y),
                width: snap(f.width),
                height: snap(f.height)
            )
        }
    }

    // Returns true when a proposed delta would not produce a visible change.
    func isDriftOnly(delta: CGPoint) -> Bool {
        abs(delta.x) < Self.driftThreshold && abs(delta.y) < Self.driftThreshold
    }

    private func snap(_ v: CGFloat) -> CGFloat { (v * 2).rounded() / 2 }
}
