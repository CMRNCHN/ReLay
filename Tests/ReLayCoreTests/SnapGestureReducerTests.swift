import ApplicationServices
import XCTest
@testable import ReLayCore

/// Gesture-level behaviour of the pure reducer, driven through the same
/// began/changed/ended sequence the event tap produces.
final class SnapGestureReducerTests: XCTestCase {

    private let screen = CGRect(x: 0, y: 25, width: 1512, height: 920)
    private let config = Config(lockThreshold: 20, cancelThreshold: 25,
                                actionThreshold: 100, flickVelocity: 800, snapDuration: 0.22)
    private lazy var window: AXUIElement = AXUIElementCreateApplication(4242)

    private func input(_ dx: CGFloat, _ dy: CGFloat, _ phase: WindowIntent.Phase,
                       window: AXUIElement? = nil) -> Input {
        let win = window ?? self.window
        return Input(dx: dx, dy: dy, phase: phase, window: win,
                     screenFrame: screen,
                     startFrame: CGRect(x: 300, y: 200, width: 900, height: 600))
    }

    /// Runs a swipe of `steps` equal deltas and returns the final state.
    private func swipe(from start: State = State(), dx: CGFloat, dy: CGFloat,
                       steps: Int = 10) -> State {
        var s = reduce(start, input(0, 0, .began), config: config)
        let stepX = dx / CGFloat(steps), stepY = dy / CGFloat(steps)
        for _ in 0..<(steps - 1) {
            s = reduce(s, input(stepX, stepY, .changed), config: config)
        }
        return reduce(s, input(stepX, stepY, .ended), config: config)
    }

    // MARK: - Happy paths

    func testLeftSwipeFromFloatingCommitsLeftHalf() {
        let s = swipe(dx: -200, dy: 0)
        XCTAssertTrue(s.hasCommitted)
        XCTAssertEqual(s.layout, .leftHalf)
        XCTAssertEqual(s.targetFrame, LayoutFrameResolver.frame(for: .leftHalf, in: screen))
        XCTAssertFalse(s.shouldRevert)
    }

    func testRightSwipeFromFloatingCommitsRightHalf() {
        let s = swipe(dx: 200, dy: 0)
        XCTAssertEqual(s.layout, .rightHalf)
    }

    func testChainedLeftSwipesGoHalfThenThird() {
        var s = swipe(dx: -200, dy: 0)
        XCTAssertEqual(s.layout, .leftHalf)
        s = swipe(from: s, dx: -200, dy: 0)
        XCTAssertEqual(s.layout, .leftThird)
    }

    func testPreviewProgressRampsBetweenLockAndActionThresholds() {
        var s = reduce(State(), input(0, 0, .began), config: config)
        s = reduce(s, input(-20, 0, .changed), config: config)
        XCTAssertEqual(s.progress, 0, "no preview before the lock threshold")
        s = reduce(s, input(-40, 0, .changed), config: config)     // 60px total
        XCTAssertEqual(s.progress, 0.5, accuracy: 0.001)
        s = reduce(s, input(-60, 0, .changed), config: config)     // 120px total
        XCTAssertEqual(s.progress, 1, accuracy: 0.001)
    }

    // MARK: - Sub-threshold gestures

    func testSubThresholdSwipeDoesNotCommit() {
        let s = swipe(dx: -60, dy: 0)
        XCTAssertFalse(s.hasCommitted)
        XCTAssertEqual(s.layout, .floating)
    }

    /// Every sub-threshold title-bar scroll ends in `shouldRevert`, and
    /// WindowRuntime turns that into an AX `setFrame` back to `startFrame` —
    /// even though nothing ever moved the real window during the gesture.
    func testSubThresholdSwipeRequestsRevertWrite() {
        let s = swipe(dx: -60, dy: 0)
        XCTAssertTrue(s.shouldRevert,
                      "sub-threshold scroll asks the runtime to rewrite the window frame")

        let sim = RuntimeMirror()
        sim.frames[101] = CGRect(x: 400, y: 300, width: 800, height: 500)
        sim.swipe(on: 101, dx: -60, dy: 0)
        XCTAssertEqual(sim.writes.count, 0,
                       "a scroll that never moved the window should not write to AX")
    }

    // MARK: - Diagonal cancel sensitivity (hypothesis 5)

    /// A 3:2 swipe — 30px across for every 20px of drift — is a completely
    /// ordinary trackpad arc, and it is cancelled instead of snapping.
    func testMildlyDiagonalSwipeIsCancelled() {
        let s = swipe(dx: -300, dy: -200, steps: 10)
        XCTAssertTrue(s.shouldRevert)
        XCTAssertFalse(s.hasCommitted)
        XCTAssertEqual(s.layout, .floating)
    }

    /// A 2:1 swipe locks onto the horizontal axis and snaps.
    func testTwoToOneDiagonalSwipeStillSnaps() {
        let s = swipe(dx: -300, dy: -150, steps: 10)
        XCTAssertTrue(s.hasCommitted)
        XCTAssertEqual(s.layout, .leftHalf)
    }

    /// The axis lock uses a strict `>` against a 1.5 ratio, so a perfectly
    /// proportional 3:2 gesture never locks and always dies at 25px.
    func testAxisLockRatioBoundaryIsExclusive() {
        var s = reduce(State(), input(0, 0, .began), config: config)
        s = reduce(s, input(-15, -10, .changed), config: config)
        XCTAssertEqual(s.accumulatedX, -15)
        XCTAssertEqual(s.accumulatedY, -10, "1.5:1 is treated as ambiguous, both axes accumulate")
        s = reduce(s, input(-15, -10, .changed), config: config)
        XCTAssertTrue(s.shouldRevert, "the ambiguous branch trips cancelThreshold at 30px")
    }

    /// cancelThreshold (25) sits between lockThreshold (20) and
    /// actionThreshold (100): the cancel window is only 5px wide after preview
    /// starts, so ambiguous gestures die right as the user sees the preview.
    func testCancelThresholdFiresAfterPreviewIsAlreadyVisible() {
        var s = reduce(State(), input(0, 0, .began), config: config)
        s = reduce(s, input(-22, -18, .changed), config: config)   // 22px, ambiguous
        XCTAssertGreaterThan(s.progress, 0, "preview is already on screen")
        XCTAssertEqual(s.targetLayout, .leftHalf)
        s = reduce(s, input(-4, -4, .changed), config: config)
        XCTAssertTrue(s.shouldRevert, "…and is then yanked away")
    }

    // MARK: - Minimize footgun (hypothesis 6)

    /// Any window that is not the last-snapped one starts at `.floating`, and
    /// `.floating` + down = minimize. A downward title-bar scroll therefore
    /// sends untracked windows to the dock.
    func testDownSwipeOnUntrackedWindowMinimizes() {
        let s = swipe(dx: 0, dy: 200)
        XCTAssertTrue(s.shouldMinimize)
        XCTAssertTrue(s.hasCommitted)
    }

    func testDownSwipeFromHalfShrinksToThirdThenMinimizes() {
        var s = swipe(dx: -200, dy: 0)
        XCTAssertEqual(s.layout, .leftHalf)
        s = swipe(from: s, dx: 0, dy: 200)
        XCTAssertEqual(s.layout, .leftThird)
        XCTAssertFalse(s.shouldMinimize)
        s = swipe(from: s, dx: 0, dy: 200)
        XCTAssertTrue(s.shouldMinimize, "third state minimizes on the next down swipe")
    }

    // MARK: - Phantom commits (hypothesis 4)

    /// The reducer happily commits a layout change with no window attached.
    /// WindowRuntime then bails out of `apply` before resetting, so the
    /// semantic layout advances while nothing on screen moves.
    func testCommitWithNoWindowStillAdvancesLayout() {
        var s = reduce(State(), Input(dx: 0, dy: 0, phase: .began, window: nil,
                                      screenFrame: .zero, startFrame: .zero), config: config)
        XCTAssertNil(s.activeWindow)
        for _ in 0..<9 {
            s = reduce(s, Input(dx: -20, dy: 0, phase: .changed, window: nil,
                                screenFrame: .zero, startFrame: .zero), config: config)
        }
        s = reduce(s, Input(dx: -20, dy: 0, phase: .ended, window: nil,
                            screenFrame: .zero, startFrame: .zero), config: config)
        XCTAssertFalse(s.hasCommitted, "a commit with no window must not happen")
        XCTAssertEqual(s.layout, .floating, "layout must not advance without a window")
    }

    /// End-to-end version of the drift: a gesture that cancels mid-flight
    /// (diagonal) and is then completed leaves the runtime believing the
    /// window moved. The window never moves, but the next gesture starts from
    /// the wrong state.
    func testCancelledThenCompletedGestureDesyncsLayoutFromScreen() {
        let sim = RuntimeMirror()
        sim.frames[101] = CGRect(x: 400, y: 300, width: 800, height: 500)

        // 1. A clean left swipe: window really is left-half now.
        sim.swipe(on: 101, dx: -200, dy: 0)
        XCTAssertEqual(sim.layout, .leftHalf)
        XCTAssertEqual(sim.frames[101], LayoutFrameResolver.frame(for: .leftHalf, in: sim.screen))
        sim.clearWrites()

        // 2. A diagonal start that trips the cancel, then the user keeps going
        //    left and finishes the swipe.
        sim.begin(on: 101)
        for _ in 0..<4 { sim.send(dx: -10, dy: -8, phase: .changed) }   // cancels
        for _ in 0..<9 { sim.send(dx: -20, dy: 0, phase: .changed) }
        sim.send(dx: -20, dy: 0, phase: .ended)

        XCTAssertEqual(sim.frames[101], LayoutFrameResolver.frame(for: .leftHalf, in: sim.screen),
                       "the window never moved")
        XCTAssertEqual(sim.layout, .leftHalf,
                       "runtime layout must still match what the user sees")
    }

    /// Follow-on symptom: once the layout has drifted to `.leftThird` while the
    /// window is visually a half, the next left swipe has no transition and
    /// silently does nothing — "snapping stopped working".
    func testDriftedLayoutSwallowsTheNextGesture() {
        let sim = RuntimeMirror()
        sim.frames[101] = CGRect(x: 400, y: 300, width: 800, height: 500)
        sim.swipe(on: 101, dx: -200, dy: 0)

        sim.begin(on: 101)
        for _ in 0..<4 { sim.send(dx: -10, dy: -8, phase: .changed) }
        for _ in 0..<9 { sim.send(dx: -20, dy: 0, phase: .changed) }
        sim.send(dx: -20, dy: 0, phase: .ended)
        sim.clearWrites()

        // User tries again, cleanly this time.
        sim.swipe(on: 101, dx: -200, dy: 0)
        XCTAssertEqual(sim.frames[101], LayoutFrameResolver.frame(for: .leftThird, in: sim.screen),
                       "a clean left swipe on a left-half window must reach the third")
    }

    // MARK: - Anchor / multi-window state (hypothesis 4, 10)

    /// Touching a different window resets the layout to `.floating`, so a
    /// window that is visibly a left half is treated as unmanaged: swiping left
    /// re-snaps it to the half it is already in instead of stepping to a third.
    func testSwitchingWindowsForgetsGeometryAndRepeatsTheSameSnap() {
        let sim = RuntimeMirror()
        sim.frames[101] = CGRect(x: 400, y: 300, width: 800, height: 500)
        sim.frames[202] = CGRect(x: 500, y: 320, width: 700, height: 480)

        sim.swipe(on: 101, dx: -200, dy: 0)            // A → left half
        sim.swipe(on: 202, dx: 200, dy: 0)             // B → right half
        sim.clearWrites()

        sim.swipe(on: 101, dx: -200, dy: 0)            // back to A, swipe left again
        XCTAssertEqual(sim.frames[101], LayoutFrameResolver.frame(for: .leftThird, in: sim.screen),
                       "layout should be inferred from the window's geometry, not from who moved last")
    }

    /// A window the runtime moved as a *companion* has no recorded layout at
    /// all, so the user's next gesture on it starts from `.floating`.
    func testCompanionWindowHasNoRecordedLayout() {
        let sim = RuntimeMirror()
        sim.frames[101] = CGRect(x: 400, y: 300, width: 800, height: 500)
        sim.frames[202] = CGRect(x: 500, y: 320, width: 700, height: 480)
        sim.companionPicker = { primary, _ in primary == 101 ? 202 : nil }

        sim.swipe(on: 101, dx: -200, dy: 0)
        XCTAssertEqual(sim.frames[202], LayoutFrameResolver.frame(for: .rightHalf, in: sim.screen))
        sim.clearWrites()

        // B is visibly a right half; swiping right should step it to a third.
        sim.swipe(on: 202, dx: 200, dy: 0)
        XCTAssertEqual(sim.frames[202], LayoutFrameResolver.frame(for: .rightThird, in: sim.screen),
                       "companion-placed windows should keep their layout state")
    }

    // MARK: - Cancelled phase

    func testCancelledPhaseClearsGesture() {
        var s = reduce(State(), input(0, 0, .began), config: config)
        s = reduce(s, input(-60, 0, .changed), config: config)
        s = reduce(s, input(0, 0, .cancelled), config: config)
        XCTAssertTrue(s.shouldRevert)
        XCTAssertEqual(s.accumulatedX, 0)
    }

    func testEventsAfterCommitAreIgnoredWithinSameGesture() {
        let s = swipe(dx: -200, dy: 0)
        XCTAssertTrue(s.hasCommitted)
        let after = reduce(s, input(-200, 0, .changed), config: config)
        XCTAssertEqual(after.layout, s.layout)
        XCTAssertEqual(after.accumulatedX, s.accumulatedX)
    }
}
