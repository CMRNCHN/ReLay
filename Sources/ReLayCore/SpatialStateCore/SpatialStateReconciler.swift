import CoreGraphics
import Accessibility

// Reads the live macOS window state via LayoutOrchestrator and populates a SpatialState.
// This is the only file in SpatialStateCore that calls AX APIs.
public final class SpatialStateReconciler {
    private let normalizer = DisplayNormalizer()

    public init() {}

    public func snapshot() -> SpatialState {
        let map = DisplaySpaceMap.current()
        let windows = LayoutOrchestrator.shared.getAllVisibleWindows()

        var models: [WindowModel] = []
        var frames: [SpatialFrame] = []

        for window in windows {
            guard let rect = LayoutOrchestrator.shared.getWindowFrame(window) else { continue }
            let spatial = normalizer.normalize(frame: rect, displayID: CGMainDisplayID())
            let bundleID = bundleID(for: window)
            let title = LayoutOrchestrator.shared.windowTitle(for: window)
            let displayID = map.displayContaining(spatial)?.id ?? CGMainDisplayID()

            let model = WindowModel(
                id: stableID(bundleID: bundleID, title: title),
                appBundleID: bundleID,
                title: title,
                frame: spatial,
                displayID: displayID,
                spaceID: nil
            )
            models.append(model)
            frames.append(spatial)
        }

        let recencyOrder = recencyOrderedBundleIDs(from: models)

        return SpatialState(
            workspace: WorkspaceModel(
                windows: models,
                displayMap: map,
                recentBundleIDs: recencyOrder
            ),
            spatialFrames: frames,
            displayMap: map,
            capturedAt: Date()
        )
    }

    // MARK: - Private

    private func bundleID(for window: AXUIElement) -> String {
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success,
              let app = NSRunningApplication(processIdentifier: pid) else { return "unknown" }
        return app.bundleIdentifier ?? "pid-\(pid)"
    }

    private func stableID(bundleID: String, title: String) -> String {
        "\(bundleID)|\(title)".data(using: .utf8).map {
            $0.reduce(0) { ($0 &<< 5) &+ UInt64($1) }
        }.map { String($0) } ?? UUID().uuidString
    }

    private func recencyOrderedBundleIDs(from windows: [WindowModel]) -> [String] {
        var seen = Set<String>()
        return windows.compactMap { w in
            guard !seen.contains(w.appBundleID) else { return nil }
            seen.insert(w.appBundleID)
            return w.appBundleID
        }
    }
}
