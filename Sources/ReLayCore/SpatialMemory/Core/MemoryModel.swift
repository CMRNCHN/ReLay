import Foundation

// Persisted learned state. Serialized to disk between sessions.
public struct MemoryModel: Codable {
    // All recognized layout patterns, ranked by frequency.
    public var patterns: [LayoutPattern]

    // App transition weights: from-bundleID → [to-bundleID → count]
    public var transitionGraph: [String: [String: Double]]

    // Rolling event log (capped to avoid unbounded growth).
    public var recentEvents: [UsageEvent]

    public var lastUpdated: Date

    // Maximum events retained in the rolling log.
    static let eventLogCap = 500

    public init(
        patterns: [LayoutPattern] = [],
        transitionGraph: [String: [String: Double]] = [:],
        recentEvents: [UsageEvent] = [],
        lastUpdated: Date = Date()
    ) {
        self.patterns        = patterns
        self.transitionGraph = transitionGraph
        self.recentEvents    = recentEvents
        self.lastUpdated     = lastUpdated
    }

    mutating func appendEvent(_ event: UsageEvent) {
        recentEvents.append(event)
        if recentEvents.count > Self.eventLogCap {
            recentEvents.removeFirst(recentEvents.count - Self.eventLogCap)
        }
        lastUpdated = Date()
    }
}
