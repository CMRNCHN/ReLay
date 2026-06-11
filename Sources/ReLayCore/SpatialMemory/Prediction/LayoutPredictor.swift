import Foundation

// Ranks stored LayoutPatterns by likelihood given the current context.
// Pure function — takes context, returns ranked candidates. No side effects.
public final class LayoutPredictor {
    private let scorer = ConfidenceScorer()
    // Minimum combined score for a pattern to be included in results.
    private static let minimumScore = 0.15

    public init() {}

    public func predict(context: PredictionContext, graph: TransitionGraph) -> [LayoutPattern] {
        let patterns = context.memoryModel.patterns
        guard !patterns.isEmpty else { return [] }

        let scored: [(pattern: LayoutPattern, score: Double)] = patterns.compactMap { pattern in
            let s = scorer.score(pattern: pattern, context: context, graph: graph)
            guard s >= Self.minimumScore else { return nil }
            return (pattern, s)
        }

        return scored
            .sorted { $0.score > $1.score }
            .map(\.pattern)
    }
}
