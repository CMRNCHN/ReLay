import CoreGraphics
import Foundation

/// Pure functions that produce a new `SpatialState` from an existing one.
/// Using reducers keeps mutations testable and keeps the store dumb.
public enum StateReducer {

    /// Shift every window origin by `delta`.
    public static func applyWorkspaceDelta(_ delta: CGPoint, to state: inout SpatialState) {
        state.workspace.windows = state.workspace.windows.map { w in
            var updated = w
            updated.frame.origin.x += delta.x
            updated.frame.origin.y += delta.y
            return updated
        }
        state.isDirty = true
        state.version += 1
    }

    /// Replace the full window list (e.g. after a fresh CGWindowList capture).
    public static func replaceWindows(_ windows: [WindowModel], in state: inout SpatialState) {
        state.workspace.windows  = windows
        state.lastSystemSnapshot = Date()
        state.isDirty            = false
        state.version           += 1
    }

    /// Mark state as clean after a successful push to macOS.
    public static func markClean(_ state: inout SpatialState) {
        state.isDirty  = false
        state.version += 1
    }

    /// Merge system windows into the internal model, preserving internal positions
    /// for known windows and adding newly discovered ones.
    public static func mergeSystemWindows(
        _ systemWindows: [WindowModel],
        into state: inout SpatialState
    ) {
        let internalByID = Dictionary(uniqueKeysWithValues: state.workspace.windows.map { ($0.id, $0) })
        var merged: [WindowModel] = []

        for sysWin in systemWindows {
            if let internal_ = internalByID[sysWin.id] {
                merged.append(internal_)   // trust internal position for known windows
            } else {
                merged.append(sysWin)      // adopt new windows from system
            }
        }

        state.workspace.windows  = merged
        state.lastSystemSnapshot = Date()
        state.version           += 1
    }
}
