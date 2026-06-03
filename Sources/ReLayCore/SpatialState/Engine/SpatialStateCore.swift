import AppKit
import CoreGraphics
import Foundation

/// The single entry point for all spatial layout mutations in ReLay.
///
/// All write paths — gesture pipeline, ActionDispatcher, programmatic —
/// converge here before touching macOS. This eliminates dual-write conflicts
/// and makes state drift measurable and correctable.
///
/// Gesture moves are motion-smoothed: raw deltas accumulate in targetOffset and
/// are drained each frame at lerpFactor (0.25), giving continuous motion without
/// per-event AX writes. State and AX converge within a few frames after a gesture.
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
    private let mover = WindowMover()

    // Reconciliation runs every 5 seconds at most — never per gesture.
    private var reconcileTimer: Timer?
    private let reconcileInterval: TimeInterval = 5

    // Motion smoothing: gesture deltas accumulate in targetOffset.
    // Each 16ms tick the display position converges toward target via lerp.
    private var targetOffset: CGPoint = .zero   // where we want windows to be
    private var currentOffset: CGPoint = .zero  // what AX currently shows
    private var smoothTimer: DispatchSourceTimer?
    private let lerpFactor: CGFloat = 0.25
    private let settleThreshold: CGFloat = 0.5

    private init(store: SpatialStateStore, reconciler: ReconciliationEngine) {
        self.store      = store
        self.reconciler = reconciler

        reconciler.onRestoreRequired = { [weak self] windows in
            self?.pushToSystem(windows)
        }

        AppLogger.log("spatial state core initialized", subsystem: "spatial-state")
    }

    // MARK: - External Write API

    /// Translate every window in the current workspace by `delta`.
    /// Called by gesture pipeline on continuous scroll events.
    /// Accumulates into targetOffset; AX writes happen at 60fps via lerp drain.
    public func applyWorkspaceMove(delta: CGPoint) {
        targetOffset.x += delta.x
        targetOffset.y += delta.y
        startSmoothTimerIfNeeded()
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

    /// Record an updated frame for a specific window without re-querying AX.
    public func notifyWindowMoved(id: String, to frame: CGRect) {
        store.mutate { state in
            if let idx = state.workspace.windows.firstIndex(where: { $0.id == id }) {
                state.workspace.windows[idx].frame = frame
                state.version += 1
            }
        }
    }

    // MARK: - Reconciliation

    /// Start periodic background reconciliation (capped at reconcileInterval, never per-gesture).
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

    // MARK: - Motion Smoothing

    private func startSmoothTimerIfNeeded() {
        guard smoothTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(flags: [], queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(16))
        timer.setEventHandler { [weak self] in
            self?.drainSmoothStep()
        }
        timer.resume()
        smoothTimer = timer
    }

    /// Each 16ms tick: lerp currentOffset toward targetOffset, apply step to state and AX.
    private func drainSmoothStep() {
        let dx = targetOffset.x - currentOffset.x
        let dy = targetOffset.y - currentOffset.y

        guard abs(dx) > settleThreshold || abs(dy) > settleThreshold else {
            // Settled — commit any residual and stop
            let residual = CGPoint(x: dx, y: dy)
            if abs(residual.x) > 0 || abs(residual.y) > 0 {
                store.mutate { StateReducer.applyWorkspaceDelta(residual, to: &$0) }
                pushCurrentStateToSystem()
            }
            smoothTimer?.cancel()
            smoothTimer = nil
            targetOffset = .zero
            currentOffset = .zero
            return
        }

        let step = CGPoint(x: dx * lerpFactor, y: dy * lerpFactor)
        currentOffset.x += step.x
        currentOffset.y += step.y

        store.mutate { StateReducer.applyWorkspaceDelta(step, to: &$0) }
        pushCurrentStateToSystem()
    }

    // MARK: - Private

    private func pushCurrentStateToSystem() {
        let windows = store.read().workspace.windows
        pushToSystem(windows)
    }

    /// Push all window frames to macOS in a single batched pass.
    /// Deliberately omits per-window focus activation — that would cause visible
    /// app-switching flicker during continuous gesture events.
    private func pushToSystem(_ windows: [WindowModel]) {
        for window in windows {
            mover.move(window: window, to: window.frame)
        }
        store.mutate { StateReducer.markClean(&$0) }
    }
}
