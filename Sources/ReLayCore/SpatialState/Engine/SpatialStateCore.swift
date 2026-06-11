import AppKit
import CoreGraphics
import Foundation

/// The single entry point for all spatial layout mutations in ReLay.
///
/// All write paths — gesture pipeline, ActionDispatcher, programmatic —
/// converge here before touching macOS. This eliminates dual-write conflicts
/// and makes state drift measurable and correctable.
///
/// Usage:
///   SpatialStateCore.shared.applyWorkspaceMove(delta: delta)
///   SpatialStateCore.shared.captureFromSystem()
public final class SpatialStateCore {

    public static let shared: SpatialStateCore = {
        let reader      = SystemStateReader()
        let initial     = SpatialState(workspace: WorkspaceModel(
            id: UUID().uuidString,
            name: "Default",
            windows: [],
            createdAt: Date()
        ))
        let store       = SpatialStateStore(initial: initial)
        let reconciler  = ReconciliationEngine(reader: reader, store: store)
        return SpatialStateCore(store: store, reconciler: reconciler)
    }()

    public let store: SpatialStateStore
    private let reconciler: ReconciliationEngine
    private let mover     = WindowMover()
    private let focusCtrl = FocusController()

    private var reconcileTimer: Timer?
    private let reconcileInterval: TimeInterval = 30

    private init(store: SpatialStateStore, reconciler: ReconciliationEngine) {
        self.store      = store
        self.reconciler = reconciler

        // When internal state wins reconciliation, push to macOS via WindowMover
        reconciler.onRestoreRequired = { [weak self] windows in
            self?.pushToSystem(windows)
        }

        AppLogger.log("spatial state core initialized", subsystem: "spatial-state")
    }

    // MARK: - External Write API

    /// Translate every window in the current workspace by `delta`.
    /// Called by gesture pipeline on continuous scroll events.
    public func applyWorkspaceMove(delta: CGPoint) {
        store.mutate { StateReducer.applyWorkspaceDelta(delta, to: &$0) }
        pushCurrentStateToSystem()
    }

    /// Replace internal model with a fresh CGWindowList capture.
    /// Call at session start or after explicit user-triggered capture.
    public func captureFromSystem() {
        reconciler.reconcile()
        AppLogger.log("explicit system capture complete", subsystem: "spatial-state")
    }

    /// Force-restore current internal model to macOS, regardless of drift.
    public func restoreToSystem() {
        let windows = store.read().workspace.windows
        pushToSystem(windows)
        store.mutate { StateReducer.markClean(&$0) }
    }

    /// Notify the core that a gesture pipeline layout change has been applied.
    /// Records the updated frames in the internal model without re-querying AX.
    public func notifyWindowMoved(id: String, to frame: CGRect) {
        store.mutate { state in
            if let idx = state.workspace.windows.firstIndex(where: { $0.id == id }) {
                state.workspace.windows[idx].frame = frame
                state.version += 1
            }
        }
    }

    // MARK: - Reconciliation

    /// Start periodic background reconciliation.
    /// Safe to call multiple times — restarts the timer if already running.
    public func startReconciliation() {
        stopReconciliation()
        let timer = Timer.scheduledTimer(
            withTimeInterval: reconcileInterval,
            repeats: true
        ) { [weak self] _ in
            self?.reconciler.reconcile()
        }
        RunLoop.main.add(timer, forMode: .common)
        reconcileTimer = timer
        AppLogger.log("reconciliation timer started interval=\(reconcileInterval)s", subsystem: "spatial-state")
    }

    public func stopReconciliation() {
        reconcileTimer?.invalidate()
        reconcileTimer = nil
    }

    // MARK: - State Access

    public func currentState() -> SpatialState {
        store.read()
    }

    // MARK: - Private

    private func pushCurrentStateToSystem() {
        let windows = store.read().workspace.windows
        pushToSystem(windows)
    }

    private func pushToSystem(_ windows: [WindowModel]) {
        for window in windows {
            focusCtrl.focus(pid: window.pid)
            mover.move(window: window, to: window.frame)
        }
        store.mutate { StateReducer.markClean(&$0) }
    }
}
