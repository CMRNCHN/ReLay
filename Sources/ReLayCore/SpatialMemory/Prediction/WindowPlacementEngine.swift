import Foundation

// Applies a predicted LayoutPattern to a SpatialState, producing a proposed new state.
// Advisory only — the caller is responsible for routing through SpatialStateCore.
public final class WindowPlacementEngine {
    // Pattern confidence must exceed this threshold before pre-positioning windows.
    public static let confidenceThreshold = 0.7

    public init() {}

    // Returns an updated SpatialState with windows pre-positioned per the pattern.
    // Windows not covered by the pattern retain their current frames.
    public func applyPrediction(_ pattern: LayoutPattern, to state: SpatialState) -> SpatialState {
        guard pattern.confidence >= Self.confidenceThreshold else { return state }

        var updated = state

        // Replace or add a WindowModel for each app the pattern covers.
        for (bundleID, frame) in pattern.windowFrames {
            if let idx = updated.workspace.windows.firstIndex(where: { $0.appBundleID == bundleID }) {
                updated.workspace.windows[idx].frame = frame
            } else {
                // App is known to this pattern but not currently open — add a placeholder.
                let model = WindowModel(
                    id: "\(bundleID)|predicted",
                    appBundleID: bundleID,
                    title: nil,
                    frame: frame,
                    displayID: state.displayMap.displays.first?.id ?? CGMainDisplayID(),
                    spaceID: nil
                )
                updated.workspace.windows.append(model)
            }
        }

        updated.spatialFrames = updated.workspace.windows.map(\.frame)
        AppLogger.log("placement engine: applied pattern confidence=\(String(format: "%.2f", pattern.confidence)) apps=\(pattern.appBundleIDs.joined(separator: ","))", subsystem: "memory")
        return updated
    }
}
