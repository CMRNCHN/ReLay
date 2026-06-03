import Foundation

// Tracks per-app focus frequency with time-decay so stale usage fades.
// Used to bias prediction toward recently and frequently used app combinations.
public final class FrequencyModel {
    // Half-life of a usage event in seconds (7 days).
    private static let halfLife: TimeInterval = 7 * 24 * 3600

    private var scores: [String: Double] = [:]    // bundleID → decayed score
    private var lastDecay: Date = Date()

    public init() {}

    public func record(bundleID: String, at date: Date = Date()) {
        applyDecay(to: date)
        scores[bundleID, default: 0] += 1
    }

    // Returns the frequency score for a bundle ID (higher = more frequent recently).
    public func score(for bundleID: String) -> Double {
        scores[bundleID] ?? 0
    }

    // Returns bundle IDs ranked by decayed frequency, highest first.
    public func ranked() -> [String] {
        scores.sorted { $0.value > $1.value }.map(\.key)
    }

    // MARK: - Private

    private func applyDecay(to now: Date) {
        let elapsed = now.timeIntervalSince(lastDecay)
        guard elapsed > 0 else { return }
        let decayFactor = pow(0.5, elapsed / Self.halfLife)
        for key in scores.keys { scores[key]! *= decayFactor }
        lastDecay = now
    }
}
