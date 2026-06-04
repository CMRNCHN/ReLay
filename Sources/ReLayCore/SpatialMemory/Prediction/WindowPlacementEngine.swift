import CoreGraphics
import Foundation

// Applies a predicted LayoutPattern to a SpatialState, producing a proposed new state.
// Advisory only — the caller is responsible for routing through SpatialStateCore.
public final class WindowPlacementEngine {
    public static let confidenceThreshold = 0.7

    public init() {}

    public func applyPrediction(_ pattern: LayoutPattern, to state: SpatialState) -> SpatialState {
        guard pattern.confidence >= Self.confidenceThreshold else { return state }

        var updated = state

        for (bundleID, frame) in pattern.windowFrames {
            if let idx = updated.workspace.windows.firstIndex(where: { $0.appBundleID == bundleID }) {
                updated.workspace.windows[idx].frame = frame
            } else {
                let model = WindowModel(
                    id: "\(bundleID)|predicted",
                    appBundleID: bundleID,
                    pid: 0,
                    title: nil,
                    frame: frame,
                    displayID: CGMainDisplayID(),
                    spaceID: nil
                )
                updated.workspace.windows.append(model)
            }
        }

        AppLogger.log("placement engine: applied pattern confidence=\(String(format: "%.2f", pattern.confidence)) apps=\(pattern.appBundleIDs.joined(separator: ","))", subsystem: "memory")
        return updated
    }
}
