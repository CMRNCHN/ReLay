import Foundation

// Main orchestrator for the Spatial Memory layer.
// Sits above SpatialStateCore and below the Window/Bridge layer.
// Memory NEVER writes to macOS directly — all proposals must flow through
// SpatialStateCore → reconciliation → SpatialToWindowBridge.
public final class SpatialMemoryEngine {
    public static let shared = SpatialMemoryEngine()

    // Whether learning and prediction are active (can be toggled for debugging or user preference).
    public var isEnabled = true

    private let predictor:       LayoutPredictor
    private let extractor:       PatternExtractor
    private let placementEngine: WindowPlacementEngine
    private let frequencyModel:  FrequencyModel
    private let transitionGraph: TransitionGraph
    private let persistence:     MemoryPersistence

    private var model: MemoryModel
    // Ordered list of recently active bundle IDs for transition recording.
    private var recentApps: [String] = []

    // Designated init for dependency injection (tests, previews).
    public init(
        predictor:       LayoutPredictor       = LayoutPredictor(),
        extractor:       PatternExtractor      = PatternExtractor(),
        placementEngine: WindowPlacementEngine = WindowPlacementEngine(),
        frequencyModel:  FrequencyModel        = FrequencyModel(),
        persistence:     MemoryPersistence     = MemoryPersistence()
    ) {
        self.predictor       = predictor
        self.extractor       = extractor
        self.placementEngine = placementEngine
        self.frequencyModel  = frequencyModel
        self.persistence     = persistence
        self.model           = persistence.load()
        self.transitionGraph = TransitionGraph(from: model.transitionGraph)
    }

    // MARK: - Learning

    // Feed a new user event into the memory system.
    // Call this whenever an intent fires, app focus changes, or a layout is applied.
    public func learn(from state: SpatialState, event: UsageEvent) {
        guard isEnabled else { return }

        model.appendEvent(event)
        frequencyModel.record(bundleID: event.appBundleID, at: event.timestamp)

        // Record app-to-app transition.
        if let previous = recentApps.last, previous != event.appBundleID {
            transitionGraph.record(from: previous, to: event.appBundleID)
        }
        recentApps.append(event.appBundleID)
        if recentApps.count > 50 { recentApps.removeFirst() }

        // Re-extract patterns incrementally (lightweight: only when a meaningful event fires).
        if event.action == .workspaceApplied || event.action == .windowMoved {
            let updated = extractor.extract(
                from: model.recentEvents,
                states: [state]
            )
            mergePatterns(updated)
        }

        model.transitionGraph = transitionGraph.serialized()
        persistence.save(model)

        AppLogger.log("memory: learned event=\(event.action) app=\(event.appBundleID) patterns=\(model.patterns.count)", subsystem: "memory")
    }

    // MARK: - Prediction

    // Returns an advisory SpatialState with predicted window positions.
    // Returns the current state unchanged if confidence is insufficient or prediction is off.
    public func predict(state: SpatialState, activeApp: String) -> SpatialState {
        guard isEnabled else { return state }

        let context = PredictionContext(
            currentState:      state,
            activeAppBundleID: activeApp,
            recentTransitions: recentApps.suffix(5).map { $0 },
            memoryModel:       model
        )

        let candidates = predictor.predict(context: context, graph: transitionGraph)

        guard let best = candidates.first else {
            AppLogger.log("memory: no prediction above threshold for app=\(activeApp)", subsystem: "memory")
            return state
        }

        AppLogger.log("memory: predicting pattern id=\(best.id.uuidString.prefix(8)) confidence=\(String(format: "%.2f", best.confidence)) for app=\(activeApp)", subsystem: "memory")
        return placementEngine.applyPrediction(best, to: state)
    }

    // MARK: - Inspection

    public var patternCount: Int { model.patterns.count }
    public var learnedPatterns: [LayoutPattern] { model.patterns }

    // MARK: - Private

    private func mergePatterns(_ incoming: [LayoutPattern]) {
        for pattern in incoming {
            if let idx = model.patterns.firstIndex(where: { $0.appSetKey == pattern.appSetKey }) {
                model.patterns[idx].frequency += pattern.frequency
                model.patterns[idx].confidence = pattern.confidence
                model.patterns[idx].lastSeen = pattern.lastSeen
                // Merge frame positions toward new observations.
                for (bundleID, frame) in pattern.windowFrames {
                    model.patterns[idx].windowFrames[bundleID] = frame
                }
            } else {
                model.patterns.append(pattern)
            }
        }
        // Keep pattern list bounded.
        if model.patterns.count > 100 {
            model.patterns = Array(model.patterns
                .sorted { $0.frequency > $1.frequency }
                .prefix(100))
        }
    }
}

// MARK: - MemoryPersistence

// Reads and writes MemoryModel to the application support directory.
public final class MemoryPersistence {
    private let url: URL

    public init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("ReLay", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("spatial_memory.json")
    }

    public func load() -> MemoryModel {
        guard let data = try? Data(contentsOf: url),
              let model = try? JSONDecoder().decode(MemoryModel.self, from: data) else {
            return MemoryModel()
        }
        AppLogger.log("memory: loaded \(model.patterns.count) patterns from disk", subsystem: "memory")
        return model
    }

    public func save(_ model: MemoryModel) {
        guard let data = try? JSONEncoder().encode(model) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
