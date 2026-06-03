import Foundation
import CoreGraphics

/// Owns the lifecycle of named layout presets.
///
/// Capture → LayoutStore → restore via LayoutApplier.
/// All mutations still flow through SpatialStateCore so the authoritative model
/// stays current after a restore.
public final class LayoutManager {

    public static let shared = LayoutManager()

    private let store   = LayoutStore.shared
    private let applier = LayoutApplier()
    private let core    = SpatialStateCore.shared

    private init() {}

    // MARK: - Capture

    /// Snapshot current window positions as a named layout and persist it.
    @discardableResult
    public func capture(name: String) -> LayoutDefinition {
        core.captureFromSystem()
        let windows = core.currentState().workspace.windows
        let layout = LayoutDefinition(name: name, windows: windows)
        store.save(layout)
        AppLogger.log(
            "layout manager: captured '\(name)' id=\(layout.id) windows=\(windows.count)",
            subsystem: "window-engine"
        )
        return layout
    }

    // MARK: - Restore

    /// Apply a saved layout by ID.
    /// Missing or non-running apps are skipped gracefully.
    public func restore(id: String) {
        guard let layout = store.layout(id: id) else {
            AppLogger.log("layout manager: no layout found for id=\(id)", subsystem: "window-engine")
            return
        }
        AppLogger.log("layout manager: restoring '\(layout.name)' id=\(id) windows=\(layout.windows.count)", subsystem: "window-engine")

        applier.apply(layout)

        // Sync authoritative state to the restored layout
        core.store.mutate { state in
            state.workspace.windows = layout.windows
            state.isDirty   = true
            state.version  += 1
        }
        core.store.mutate { StateReducer.markClean(&$0) }
    }

    // MARK: - List

    public func listLayouts() -> [LayoutDefinition] {
        store.all()
    }
}
