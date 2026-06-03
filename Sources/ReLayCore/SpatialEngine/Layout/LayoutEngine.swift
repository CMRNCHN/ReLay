import CoreGraphics

// Pure spatial transform layer. No AX calls, no macOS API dependencies.
// Input: array of SpatialFrames + a delta. Output: stable, non-overlapping SpatialFrames.
public final class LayoutEngine {
    private let collisionResolver = CollisionResolver()
    private let stabilizer = LayoutStabilizer()

    public init() {}

    // Translates all frames by delta, resolves collisions, then stabilizes.
    public func applyTransform(frames: [SpatialFrame], delta: CGPoint) -> [SpatialFrame] {
        guard !stabilizer.isDriftOnly(delta: delta) else { return frames }
        let moved = frames.map {
            SpatialFrame(x: $0.x + delta.x, y: $0.y + delta.y,
                         width: $0.width, height: $0.height)
        }
        let resolved = collisionResolver.resolve(moved)
        return stabilizer.stabilize(resolved)
    }

    // Applies a transform to a single frame without collision resolution.
    public func applyTransform(frame: SpatialFrame, delta: CGPoint) -> SpatialFrame {
        guard !stabilizer.isDriftOnly(delta: delta) else { return frame }
        let moved = SpatialFrame(x: frame.x + delta.x, y: frame.y + delta.y,
                                 width: frame.width, height: frame.height)
        return stabilizer.stabilize([moved])[0]
    }
}
