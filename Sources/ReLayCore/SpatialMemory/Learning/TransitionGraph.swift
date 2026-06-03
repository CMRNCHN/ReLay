import Foundation

// Records how users move between apps over time (Markov chain over bundle IDs).
// Pure value operations — no async, no persistence (caller owns the MemoryModel).
public final class TransitionGraph {
    private var graph: [String: [String: Int]] = [:]

    public init(from stored: [String: [String: Double]] = [:]) {
        for (from, targets) in stored {
            graph[from] = targets.mapValues { Int($0) }
        }
    }

    // Record a transition from one bundle ID to another.
    public func record(from: String, to: String) {
        guard from != to else { return }
        graph[from, default: [:]][to, default: 0] += 1
    }

    // Probability that the user switches to `to` given they are in `from` (0–1).
    public func probability(from: String, to: String) -> Double {
        let row = graph[from] ?? [:]
        let total = row.values.reduce(0, +)
        guard total > 0 else { return 0 }
        return Double(row[to] ?? 0) / Double(total)
    }

    // Returns bundle IDs most likely to follow `from`, ranked by probability.
    public func likelyNext(from: String, top k: Int = 3) -> [(bundleID: String, probability: Double)] {
        let row = graph[from] ?? [:]
        let total = row.values.reduce(0, +)
        guard total > 0 else { return [] }
        return row
            .map { ($0.key, Double($0.value) / Double(total)) }
            .sorted { $0.1 > $1.1 }
            .prefix(k)
            .map { ($0.0, $0.1) }
    }

    // Serializable form for storage in MemoryModel.
    public func serialized() -> [String: [String: Double]] {
        graph.mapValues { $0.mapValues { Double($0) } }
    }
}
