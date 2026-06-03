import CoreGraphics

// Deterministic O(n²) collision avoidance with bounded cascade depth.
// Prevents windows from stacking exactly on top of each other after transforms.
public final class CollisionResolver {
    private static let nudge: CGFloat = 20
    private static let maxPasses = 20

    public init() {}

    // Returns frames in the same order with overlapping pairs nudged apart.
    public func resolve(_ frames: [SpatialFrame]) -> [SpatialFrame] {
        guard frames.count > 1 else { return frames }
        var result = frames
        for pass in 0..<Self.maxPasses {
            var changed = false
            for i in 0..<result.count {
                for j in (i + 1)..<result.count {
                    if result[i].intersects(result[j]) {
                        result[j].x += Self.nudge
                        result[j].y += Self.nudge
                        changed = true
                    }
                }
            }
            if !changed {
                if pass > 0 {
                    AppLogger.log("collision resolved in \(pass + 1) passes", subsystem: "spatial")
                }
                return result
            }
        }
        AppLogger.log("collision resolver hit max passes (\(Self.maxPasses))", subsystem: "spatial")
        return result
    }
}
