import Foundation

/// Compares system reality vs. internal model and corrects whichever is wrong.
///
/// Direction-of-truth heuristic:
///   drift < 5%  → no action (within tolerance)
///   5–50%       → internal wins: re-assert ReLay layout via WindowEngine
///   > 50%       → system wins: external moves dominate, absorb into internal model
public final class ReconciliationEngine {

    private let reader:   SystemStateReader
    private let store:    SpatialStateStore
    private let detector: DriftDetector

    /// Called when internal state should be pushed to macOS (internal wins).
    public var onRestoreRequired: (([WindowModel]) -> Void)?

    // Low-drift threshold below which we do nothing
    private let idleThreshold:   Double = 0.05
    // High-drift threshold above which system is treated as truth
    private let systemTrueThreshold: Double = 0.50

    public init(reader: SystemStateReader, store: SpatialStateStore) {
        self.reader   = reader
        self.store    = store
        self.detector = DriftDetector()
    }

    // MARK: - Reconcile

    @discardableResult
    public func reconcile() -> Double {
        let systemWindows   = reader.readSystemState()
        let internalWindows = store.read().workspace.windows

        let drift = detector.computeDrift(system: systemWindows, internal: internalWindows)

        AppLogger.log(
            "reconcile drift=\(String(format: "%.2f", drift)) systemWindows=\(systemWindows.count) internalWindows=\(internalWindows.count)",
            subsystem: "spatial-state"
        )

        guard drift > idleThreshold else { return drift }

        if drift > systemTrueThreshold {
            // System wins: too much divergence — absorb current system state
            store.mutate { StateReducer.replaceWindows(systemWindows, in: &$0) }
            AppLogger.log("reconcile: system wins, absorbing \(systemWindows.count) windows", subsystem: "spatial-state")
        } else {
            // Internal wins: re-apply ReLay layout to macOS
            let windows = internalWindows
            AppLogger.log("reconcile: internal wins, restoring \(windows.count) windows", subsystem: "spatial-state")
            onRestoreRequired?(windows)
        }

        return drift
    }
}
