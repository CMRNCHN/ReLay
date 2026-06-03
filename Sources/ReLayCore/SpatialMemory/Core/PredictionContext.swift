import Foundation

// Snapshot of everything the predictor needs at decision time.
public struct PredictionContext {
    public let currentState: SpatialState
    public let activeAppBundleID: String
    public let recentTransitions: [String]  // ordered from-bundleIDs, most recent last
    public let memoryModel: MemoryModel
    public let timestamp: Date

    public init(
        currentState: SpatialState,
        activeAppBundleID: String,
        recentTransitions: [String],
        memoryModel: MemoryModel,
        timestamp: Date = Date()
    ) {
        self.currentState       = currentState
        self.activeAppBundleID  = activeAppBundleID
        self.recentTransitions  = recentTransitions
        self.memoryModel        = memoryModel
        self.timestamp          = timestamp
    }
}
