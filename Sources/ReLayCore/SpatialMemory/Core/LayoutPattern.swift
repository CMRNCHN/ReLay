import CoreGraphics
import Foundation

// A recurring spatial configuration identified across sessions.
public struct LayoutPattern: Codable, Hashable, Identifiable {
    public let id: UUID
    // Bundle IDs of apps present in this pattern (order-independent key).
    public let appBundleIDs: [String]
    // Bundle ID → last-observed SpatialFrame for that app's primary window.
    public var windowFrames: [String: CGRect]
    // How many times this configuration has been observed.
    public var frequency: Int
    // 0–1: fraction of observations this pattern was complete vs. partial.
    public var confidence: Double
    public var lastSeen: Date

    public init(
        id: UUID = UUID(),
        appBundleIDs: [String],
        windowFrames: [String: CGRect],
        frequency: Int = 1,
        confidence: Double = 0,
        lastSeen: Date = Date()
    ) {
        self.id           = id
        self.appBundleIDs = appBundleIDs.sorted()   // canonical order
        self.windowFrames = windowFrames
        self.frequency    = frequency
        self.confidence   = confidence
        self.lastSeen     = lastSeen
    }

    // Sorted app-set key for identity comparison.
    var appSetKey: String { appBundleIDs.sorted().joined(separator: "|") }

    // Jaccard similarity against another app set (0–1).
    func similarity(to other: LayoutPattern) -> Double {
        let a = Set(appBundleIDs), b = Set(other.appBundleIDs)
        guard !a.isEmpty || !b.isEmpty else { return 1 }
        return Double(a.intersection(b).count) / Double(a.union(b).count)
    }
}
