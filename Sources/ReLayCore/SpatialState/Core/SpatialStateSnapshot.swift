import CoreGraphics

/// A paired view of system-reported state vs. ReLay's internal model.
/// Used by `ReconciliationEngine` to decide direction of correction.
public struct SpatialStateSnapshot {

    public let systemWindows:   [WindowModel]
    public let internalWindows: [WindowModel]

    /// Fraction of windows whose on-screen position diverges from the internal model.
    /// 0.0 = perfect sync, 1.0 = completely diverged.
    public func driftScore() -> Double {
        guard !internalWindows.isEmpty else { return systemWindows.isEmpty ? 0.0 : 1.0 }

        let internalByID = Dictionary(uniqueKeysWithValues: internalWindows.map { ($0.id, $0) })
        var mismatchCount = 0

        for sysWin in systemWindows {
            guard let internalWin = internalByID[sysWin.id] else {
                // Window present in system but missing from internal model
                mismatchCount += 1
                continue
            }
            let dx = abs(sysWin.frame.origin.x - internalWin.frame.origin.x)
            let dy = abs(sysWin.frame.origin.y - internalWin.frame.origin.y)
            let dw = abs(sysWin.frame.width    - internalWin.frame.width)
            let dh = abs(sysWin.frame.height   - internalWin.frame.height)
            if dx > 5 || dy > 5 || dw > 5 || dh > 5 {
                mismatchCount += 1
            }
        }

        return Double(mismatchCount) / Double(max(systemWindows.count, 1))
    }
}
