import Foundation

// Identifies recurring spatial configurations by clustering similar window sets.
// Pure function: no side effects, no persistence.
public final class PatternExtractor {
    // Minimum Jaccard similarity to merge two observations into the same pattern.
    private static let mergeThreshold = 0.6
    // Minimum occurrences before a pattern is considered learned.
    private static let minFrequency = 2

    public init() {}

    // Produces a deduplicated, frequency-ranked pattern list from the spatial state history.
    // `states` must be provided in chronological order.
    public func extract(from history: [UsageEvent], states: [SpatialState]) -> [LayoutPattern] {
        var candidates: [LayoutPattern] = []

        for state in states {
            let appSet = Set(state.workspace.windows.map(\.appBundleID))
            guard appSet.count >= 2 else { continue }

            let frames = Dictionary(uniqueKeysWithValues: state.workspace.windows.map {
                ($0.appBundleID, $0.frame)
            })

            let incoming = LayoutPattern(
                appBundleIDs: Array(appSet),
                windowFrames: frames
            )

            if let idx = candidates.firstIndex(where: {
                $0.similarity(to: incoming) >= Self.mergeThreshold
            }) {
                candidates[idx].frequency += 1
                candidates[idx].lastSeen = state.capturedAt
                // Update frames toward observed position (moving average, weight = 1/frequency).
                let weight = 1.0 / Double(candidates[idx].frequency)
                for (bundleID, frame) in frames {
                    if let existing = candidates[idx].windowFrames[bundleID] {
                        candidates[idx].windowFrames[bundleID] = lerp(existing, frame, t: weight)
                    } else {
                        candidates[idx].windowFrames[bundleID] = frame
                    }
                }
            } else {
                candidates.append(incoming)
            }
        }

        // Compute confidence: frequency as a fraction of max observed frequency.
        let maxFreq = Double(candidates.map(\.frequency).max() ?? 1)
        for i in candidates.indices {
            candidates[i].confidence = Double(candidates[i].frequency) / maxFreq
        }

        return candidates
            .filter { $0.frequency >= Self.minFrequency }
            .sorted { $0.frequency > $1.frequency }
    }

    // MARK: - Private

    // Linear interpolation between two SpatialFrames for frame averaging.
    private func lerp(_ a: SpatialFrame, _ b: SpatialFrame, t: Double) -> SpatialFrame {
        let tc = CGFloat(t)
        return SpatialFrame(
            x:      a.x      + (b.x      - a.x)      * tc,
            y:      a.y      + (b.y      - a.y)      * tc,
            width:  a.width  + (b.width  - a.width)  * tc,
            height: a.height + (b.height - a.height) * tc
        )
    }
}
