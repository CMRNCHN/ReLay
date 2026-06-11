import CoreGraphics

/// Computes a drift score between two window sets, matched by CGWindowID.
/// Suitable for calling on a background queue — no AX or AppKit calls.
public final class DriftDetector {

    /// Tolerance in points; differences smaller than this are ignored.
    public var positionTolerance: CGFloat = 5
    public var sizeTolerance:     CGFloat = 5

    public init() {}

    /// Returns a value in [0, 1]: fraction of shared windows whose frames diverge.
    public func computeDrift(system: [WindowModel], internal: [WindowModel]) -> Double {
        guard !`internal`.isEmpty else { return system.isEmpty ? 0.0 : 1.0 }

        let internalByID = Dictionary(uniqueKeysWithValues: `internal`.map { ($0.id, $0) })
        var matched     = 0
        var mismatched  = 0

        for sysWin in system {
            guard let int = internalByID[sysWin.id] else { continue }
            matched += 1
            let diverges =
                abs(sysWin.frame.origin.x - int.frame.origin.x) > positionTolerance ||
                abs(sysWin.frame.origin.y - int.frame.origin.y) > positionTolerance ||
                abs(sysWin.frame.width    - int.frame.width)    > sizeTolerance     ||
                abs(sysWin.frame.height   - int.frame.height)   > sizeTolerance
            if diverges { mismatched += 1 }
        }

        guard matched > 0 else { return 0.0 }
        return Double(mismatched) / Double(matched)
    }
}
