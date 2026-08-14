import ApplicationServices
import CoreGraphics
import XCTest
@testable import ReLayCore

/// Headless mirror of `WindowRuntime.didReceive` + `WindowRuntime.apply`
/// (Sources/ReLayCore/Core/WindowRuntime.swift). Everything that touches AX,
/// AppKit overlays or haptics is replaced by a recorder so the gesture state
/// machine can be exercised in a unit test.
///
/// This must stay structurally identical to `WindowRuntime`; the assertions in
/// `RuntimeMirrorFidelityTests` pin the parts that are cheap to verify.
final class RuntimeMirror {

    struct Write: Equatable, CustomStringConvertible {
        let window: pid_t
        let frame: CGRect
        var description: String { "win \(window) → \(frame)" }
    }

    // Fake world
    var screen: CGRect = CGRect(x: 0, y: 25, width: 1512, height: 920)
    var frames: [pid_t: CGRect] = [:]
    var bundleIDs: [pid_t: String] = [:]
    /// Window the title-bar hit test resolves at `.began`.
    var hitWindow: pid_t?
    /// Stand-in for `applyCompanionLayouts` → `bestCompanion`.
    var companionPicker: ((pid_t, WindowLayoutState) -> pid_t?)?
    var config = Config(
        lockThreshold: 20,
        cancelThreshold: 25,
        actionThreshold: 100,
        flickVelocity: 800,
        snapDuration: 0.22,
        layoutGap: 8
    )

    // Recorded effects
    private(set) var writes: [Write] = []
    private(set) var minimized: [pid_t] = []
    private(set) var unminimized: [pid_t] = []
    private(set) var haptics = 0
    /// Peers stashed when entering fullscreen (mirror of WindowRuntime).
    private var minimizedForFullscreen: [(pid: pid_t, frame: CGRect)] = []

    // Mirrored runtime state
    private(set) var state = State()
    private var activeBundleID = ""

    var layout: WindowLayoutState { state.layout }

    // MARK: - Identity helpers

    static func element(_ pid: pid_t) -> AXUIElement { AXUIElementCreateApplication(pid) }

    private static func pid(of element: AXUIElement) -> pid_t {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        return pid
    }

    // MARK: - Gesture driving

    func begin(on window: pid_t) {
        hitWindow = window
        send(dx: 0, dy: 0, phase: .began)
    }

    func send(dx: CGFloat, dy: CGFloat, phase: WindowIntent.Phase) {
        didReceive(WindowIntent(dx: dx, dy: dy, phase: phase, location: .zero))
    }

    /// began → n × changed → ended, mimicking a trackpad swipe delivered in
    /// `steps` equal deltas.
    func swipe(on window: pid_t, dx: CGFloat, dy: CGFloat, steps: Int = 10) {
        begin(on: window)
        let stepX = dx / CGFloat(steps), stepY = dy / CGFloat(steps)
        for _ in 0..<(steps - 1) { send(dx: stepX, dy: stepY, phase: .changed) }
        send(dx: stepX, dy: stepY, phase: .ended)
    }

    // MARK: - Mirror of WindowRuntime.didReceive

    private func didReceive(_ intent: WindowIntent) {
        let window: AXUIElement?
        if intent.phase == .began {
            window = hitWindow.map { Self.element($0) }
        } else {
            window = state.activeWindow
        }
        let startFrame: CGRect
        if intent.phase == .began, let window {
            startFrame = frames[Self.pid(of: window)] ?? .zero
        } else {
            startFrame = state.startFrame
        }
        let resolvedScreen = window != nil ? screen : .zero

        if intent.phase == .began, let window {
            activeBundleID = bundleIDs[Self.pid(of: window)] ?? "com.example.app"
            state.layout = LayoutFrameResolver.layout(matching: startFrame, in: resolvedScreen)
        }
        let input = Input(dx: intent.dx, dy: intent.dy,
                          phase: intent.phase, window: window,
                          screenFrame: resolvedScreen, startFrame: startFrame,
                          allowCenter: frames.count <= 1)
        let prev = state
        state = reduce(state, input, config: config)
        apply(prev: prev, curr: state)
    }

    // MARK: - Mirror of WindowRuntime.apply

    private func apply(prev: State, curr: State) {
        if curr.hasCommitted && !prev.hasCommitted {
            guard let window = curr.activeWindow else {
                resetGestureState(preservingLayout: prev.layout, floatingFrame: curr.floatingFrame)
                return
            }
            let pid = Self.pid(of: window)

            if curr.shouldMinimize {
                if WindowMutabilityPolicy.decision(for: activeBundleID) == .allow {
                    let peers = frames.keys.filter { $0 != pid }.sorted().filter { other in
                        let frame = frames[other] ?? .zero
                        let overlap = frame.intersection(screen)
                        guard overlap.width > CompanionSelector.minOverlapEdge,
                              overlap.height > CompanionSelector.minOverlapEdge,
                              overlap.width * overlap.height > CompanionSelector.minOverlapArea
                        else { return false }
                        let bundleID = bundleIDs[other] ?? "com.example.app"
                        return WindowMutabilityPolicy.decision(for: bundleID) == .allow
                    }
                    minimized.append(pid)
                    haptics += 1
                    if peers.count == 1 {
                        let full = LayoutFrameResolver.frame(for: .fullscreen, in: screen)
                        writes.append(Write(window: peers[0], frame: full))
                        frames[peers[0]] = full
                    }
                }
                resetGestureState(preservingLayout: .floating, floatingFrame: curr.floatingFrame)
                return
            }

            var committedLayout = prev.layout
            if WindowMutabilityPolicy.decision(for: activeBundleID) == .allow {
                writes.append(Write(window: pid, frame: curr.targetFrame))
                frames[pid] = curr.targetFrame
                committedLayout = curr.layout
                haptics += 1
                if WindowRuntime.shouldMinimizeOthers(from: prev.layout, to: curr.layout) {
                    minimizeOtherWindows(excluding: pid)
                } else if WindowRuntime.shouldRestoreMinimized(from: prev.layout, to: curr.layout) {
                    restoreMinimizedCompanions(primary: pid, layout: curr.layout)
                } else {
                    applyCompanionLayouts(primary: pid, layout: curr.layout)
                }
            }
            resetGestureState(preservingLayout: committedLayout, floatingFrame: curr.floatingFrame)
            return
        }

        if curr.shouldRevert {
            if let window = curr.activeWindow,
               !curr.startFrame.isEmpty,
               WindowMutabilityPolicy.decision(for: activeBundleID) == .allow,
               let live = frames[Self.pid(of: window)], live != curr.startFrame {
                let pid = Self.pid(of: window)
                writes.append(Write(window: pid, frame: curr.startFrame))
                frames[pid] = curr.startFrame
            }
            resetGestureState(preservingLayout: curr.layout, floatingFrame: curr.floatingFrame)
            return
        }
    }

    private func applyCompanionLayouts(primary: pid_t, layout: WindowLayoutState) {
        guard let picker = companionPicker, let companion = picker(primary, layout) else { return }
        let companionFrames = LayoutFrameResolver.companionFrames(for: layout, count: 1, in: screen)
        guard let frame = companionFrames.first else { return }
        writes.append(Write(window: companion, frame: frame))
        frames[companion] = frame
    }

    private func minimizeOtherWindows(excluding primary: pid_t) {
        let others = frames.keys.filter { $0 != primary }.sorted()
        var stashed: [(pid: pid_t, frame: CGRect)] = []
        for pid in others {
            let frame = frames[pid] ?? .zero
            let overlap = frame.intersection(screen)
            guard overlap.width > CompanionSelector.minOverlapEdge,
                  overlap.height > CompanionSelector.minOverlapEdge,
                  overlap.width * overlap.height > CompanionSelector.minOverlapArea
            else { continue }
            let bundleID = bundleIDs[pid] ?? "com.example.app"
            guard WindowMutabilityPolicy.decision(for: bundleID) == .allow else { continue }
            minimized.append(pid)
            stashed.append((pid: pid, frame: frame))
        }
        minimizedForFullscreen = stashed
    }

    private func restoreMinimizedCompanions(primary: pid_t, layout: WindowLayoutState) {
        let peers = minimizedForFullscreen
        minimizedForFullscreen = []
        guard !peers.isEmpty else {
            applyCompanionLayouts(primary: primary, layout: layout)
            return
        }
        let leftover = LayoutFrameResolver.companionFrames(for: layout, count: 1, in: screen).first
        for (index, peer) in peers.enumerated() {
            unminimized.append(peer.pid)
            minimized.removeAll { $0 == peer.pid }
            let target: CGRect?
            if index == 0, let leftover, AXWindowOps.isWritableFrame(leftover) {
                target = leftover
            } else if AXWindowOps.isWritableFrame(peer.frame) {
                target = peer.frame
            } else {
                target = nil
            }
            if let target {
                writes.append(Write(window: peer.pid, frame: target))
                frames[peer.pid] = target
            }
        }
    }

    private func resetGestureState(preservingLayout layout: WindowLayoutState, floatingFrame: CGRect) {
        state = State()
        state.layout = layout
        state.floatingFrame = floatingFrame
    }

    // MARK: - Assertions helpers

    var lastWrite: Write? { writes.last }

    func clearWrites() { writes.removeAll() }
}

/// Sanity checks on the fake-identity trick the mirror relies on.
final class RuntimeMirrorFidelityTests: XCTestCase {

    func testFakeWindowElementsHaveStableIdentity() {
        let a1 = RuntimeMirror.element(101)
        let a2 = RuntimeMirror.element(101)
        let b = RuntimeMirror.element(102)
        XCTAssertTrue(CFEqual(a1, a2), "same pid must produce CFEqual elements")
        XCTAssertFalse(CFEqual(a1, b), "different pids must not be CFEqual")
    }

    func testMirrorAppliesFrameOnCommittedSwipe() {
        let sim = RuntimeMirror()
        sim.frames[101] = CGRect(x: 400, y: 300, width: 800, height: 500)
        sim.swipe(on: 101, dx: -200, dy: 0)
        XCTAssertEqual(sim.layout, .leftHalf)
        XCTAssertEqual(sim.lastWrite?.frame,
                       LayoutFrameResolver.frame(for: .leftHalf, in: sim.screen))
    }
}
