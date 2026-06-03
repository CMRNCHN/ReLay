import Foundation

// Computes a final confidence score for a LayoutPattern given a PredictionContext.
// Combines pattern base confidence, transition probability, and recency.
public struct ConfidenceScorer {
    // Weight factors — must sum to 1.
    private static let patternWeight:    Double = 0.50
    private static let transitionWeight: Double = 0.35
    private static let recencyWeight:    Double = 0.15
    // Decay constant: confidence halves every 14 days since pattern was last seen.
    private static let recencyHalfLife: TimeInterval = 14 * 24 * 3600

    public init() {}

    public func score(
        pattern: LayoutPattern,
        context: PredictionContext,
        graph: TransitionGraph
    ) -> Double {
        let patternScore = pattern.confidence

        // Transition score: probability of reaching any app in the pattern from the current app.
        let transitionScore = pattern.appBundleIDs.map { bundleID in
            graph.probability(from: context.activeAppBundleID, to: bundleID)
        }.max() ?? 0

        // Recency score: exponential decay from last time this pattern was seen.
        let elapsed = context.timestamp.timeIntervalSince(pattern.lastSeen)
        let recencyScore = pow(0.5, max(0, elapsed) / Self.recencyHalfLife)

        let combined = Self.patternWeight    * patternScore
                     + Self.transitionWeight * transitionScore
                     + Self.recencyWeight    * recencyScore

        return min(1, max(0, combined))
    }
}
