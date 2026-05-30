import XCTest
@testable import ReLayCore

// MARK: - LayoutTransitionGraph

final class TransitionGraphTests: XCTestCase {

    private let graph = LayoutTransitionGraph()

    // MARK: Horizontal — enter columns from neutral states

    func testNeutralStatesGoLeftToLeftHalf() {
        for state in [WindowLayoutState.floating, .center, .fullscreen] {
            XCTAssertEqual(graph.nextState(from: state, moving: .left), .leftHalf, "from \(state)")
        }
    }

    func testNeutralStatesGoRightToRightHalf() {
        for state in [WindowLayoutState.floating, .center, .fullscreen] {
            XCTAssertEqual(graph.nextState(from: state, moving: .right), .rightHalf, "from \(state)")
        }
    }

    // MARK: Horizontal — navigate within columns

    func testLeftHalfPushesToLeftThird() {
        XCTAssertEqual(graph.nextState(from: .leftHalf, moving: .left), .leftThird)
    }

    func testLeftHalfJumpsToRightHalf() {
        XCTAssertEqual(graph.nextState(from: .leftHalf, moving: .right), .rightHalf)
    }

    func testRightHalfPushesToRightThird() {
        XCTAssertEqual(graph.nextState(from: .rightHalf, moving: .right), .rightThird)
    }

    func testRightHalfJumpsToLeftHalf() {
        XCTAssertEqual(graph.nextState(from: .rightHalf, moving: .left), .leftHalf)
    }

    func testLeftThirdPullsToLeftHalf() {
        XCTAssertEqual(graph.nextState(from: .leftThird, moving: .right), .leftHalf)
    }

    func testRightThirdPullsToRightHalf() {
        XCTAssertEqual(graph.nextState(from: .rightThird, moving: .left), .rightHalf)
    }

    // MARK: Horizontal — cross-column jumps from sixths

    func testLeftTopSixthJumpsRightToRightTopSixth() {
        XCTAssertEqual(graph.nextState(from: .leftTopSixth, moving: .right), .rightTopSixth)
    }

    func testLeftBottomSixthJumpsRightToRightBottomSixth() {
        XCTAssertEqual(graph.nextState(from: .leftBottomSixth, moving: .right), .rightBottomSixth)
    }

    func testRightTopSixthJumpsLeftToLeftTopSixth() {
        XCTAssertEqual(graph.nextState(from: .rightTopSixth, moving: .left), .leftTopSixth)
    }

    func testRightBottomSixthJumpsLeftToLeftBottomSixth() {
        XCTAssertEqual(graph.nextState(from: .rightBottomSixth, moving: .left), .leftBottomSixth)
    }

    // MARK: Vertical — no graph entries (handled as direct actions in SpatialTransitionEngine)
    // Up = enlarge to fullscreen; Down = minimize. Neither lives in the transition graph.

    func testVerticalGesturesHaveNoGraphEntries() {
        let allStates = WindowLayoutState.allCases
        for state in allStates {
            XCTAssertNil(graph.nextState(from: state, moving: .up),   "unexpected up entry from \(state)")
            XCTAssertNil(graph.nextState(from: state, moving: .down), "unexpected down entry from \(state)")
        }
    }

    // MARK: Edge resistance — no transition defined

    func testLeftThirdResistsLeft() {
        XCTAssertNil(graph.nextState(from: .leftThird, moving: .left))
    }

    func testRightThirdResistsRight() {
        XCTAssertNil(graph.nextState(from: .rightThird, moving: .right))
    }

    func testFullscreenResistsUp() {
        XCTAssertNil(graph.nextState(from: .fullscreen, moving: .up))
    }

    func testFullscreenResistsLeft() {
        // fullscreen goes to leftHalf on .left — this is defined
        XCTAssertEqual(graph.nextState(from: .fullscreen, moving: .left), .leftHalf)
    }

    func testLeftTopSixthHasNoLeftTransition() {
        XCTAssertNil(graph.nextState(from: .leftTopSixth, moving: .left))
    }

    func testRightTopSixthHasNoRightTransition() {
        XCTAssertNil(graph.nextState(from: .rightTopSixth, moving: .right))
    }
}

// MARK: - LayoutResolver geometry

final class LayoutResolverTests: XCTestCase {

    private let resolver = LayoutResolver.shared
    private let screen   = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    func testFloatingReturnsZero() {
        XCTAssertEqual(resolver.frame(for: .floating, on: screen), .zero)
    }

    func testFullscreenFillsScreen() {
        XCTAssertEqual(resolver.frame(for: .fullscreen, on: screen), screen)
    }

    func testCenterIsNarrowAndCentered() {
        let f = resolver.frame(for: .center, on: screen)
        let expectedW = (1920 * 0.72).rounded()
        let expectedX = ((1920 - expectedW) / 2).rounded()
        XCTAssertEqual(f.width,    expectedW)
        XCTAssertEqual(f.origin.x, expectedX)
        XCTAssertEqual(f.height,   1080)
        XCTAssertEqual(f.origin.y, 0)
    }

    func testLeftHalfIsExactlyHalfWidth() {
        let f = resolver.frame(for: .leftHalf, on: screen)
        XCTAssertEqual(f.origin.x, 0)
        XCTAssertEqual(f.width,    (1920 * 0.5).rounded())
        XCTAssertEqual(f.height,   1080)
    }

    func testRightHalfIsExactlyHalfWidthOnRight() {
        let f = resolver.frame(for: .rightHalf, on: screen)
        let w = (1920 * 0.5).rounded()
        XCTAssertEqual(f.origin.x, 1920 - w)
        XCTAssertEqual(f.width,    w)
        XCTAssertEqual(f.height,   1080)
    }

    func testLeftHalfAndRightHalfCoverFullWidth() {
        let lf = resolver.frame(for: .leftHalf, on: screen)
        let rf = resolver.frame(for: .rightHalf, on: screen)
        XCTAssertEqual(lf.width + rf.width, 1920, accuracy: 1)
    }

    func testLeftThirdIsOneThirdWidth() {
        let f = resolver.frame(for: .leftThird, on: screen)
        XCTAssertEqual(f.origin.x, 0)
        XCTAssertEqual(f.width,    (1920.0 / 3).rounded())
        XCTAssertEqual(f.height,   1080)
    }

    func testRightThirdIsOneThirdWidthOnRight() {
        let f = resolver.frame(for: .rightThird, on: screen)
        let w = (1920.0 / 3).rounded()
        XCTAssertEqual(f.origin.x, 1920 - w)
        XCTAssertEqual(f.width,    w)
        XCTAssertEqual(f.height,   1080)
    }

    func testLeftTopSixthIsTopHalfOfLeftThird() {
        let f  = resolver.frame(for: .leftTopSixth, on: screen)
        let lt = resolver.frame(for: .leftThird,    on: screen)
        XCTAssertEqual(f.origin.x, lt.origin.x)
        XCTAssertEqual(f.width,    lt.width)
        XCTAssertEqual(f.origin.y, 0)
        XCTAssertEqual(f.height,   (1080.0 / 2).rounded())
    }

    func testLeftBottomSixthIsBottomHalfOfLeftThird() {
        let f  = resolver.frame(for: .leftBottomSixth, on: screen)
        let lt = resolver.frame(for: .leftThird,       on: screen)
        let h  = (1080.0 / 2).rounded()
        XCTAssertEqual(f.origin.x, lt.origin.x)
        XCTAssertEqual(f.width,    lt.width)
        XCTAssertEqual(f.origin.y, h)
        XCTAssertEqual(f.height,   h)
    }

    func testRightTopSixthIsTopHalfOfRightThird() {
        let f  = resolver.frame(for: .rightTopSixth, on: screen)
        let rt = resolver.frame(for: .rightThird,    on: screen)
        XCTAssertEqual(f.origin.x, rt.origin.x)
        XCTAssertEqual(f.width,    rt.width)
        XCTAssertEqual(f.origin.y, 0)
        XCTAssertEqual(f.height,   (1080.0 / 2).rounded())
    }

    func testRightBottomSixthIsBottomHalfOfRightThird() {
        let f  = resolver.frame(for: .rightBottomSixth, on: screen)
        let rt = resolver.frame(for: .rightThird,       on: screen)
        let h  = (1080.0 / 2).rounded()
        XCTAssertEqual(f.origin.x, rt.origin.x)
        XCTAssertEqual(f.width,    rt.width)
        XCTAssertEqual(f.origin.y, h)
        XCTAssertEqual(f.height,   h)
    }

    func testSixthsStackToTheirThirdHeight() {
        let top    = resolver.frame(for: .leftTopSixth,    on: screen)
        let bottom = resolver.frame(for: .leftBottomSixth, on: screen)
        XCTAssertEqual(top.height + bottom.height, 1080, accuracy: 1)
        XCTAssertEqual(top.maxY, bottom.minY, accuracy: 1)
    }

    // MARK: LayoutResolver — frame inference

    func testInferStateRoundTripsAllNamedStates() {
        let named = WindowLayoutState.allCases.filter { $0 != .floating }
        for state in named {
            let f = resolver.frame(for: state, on: screen)
            let inferred = resolver.inferState(from: f, on: screen)
            XCTAssertEqual(inferred, state, "round-trip failed for \(state)")
        }
    }

    func testInferStateReturnsFloatingForUnknownFrame() {
        let odd = CGRect(x: 123, y: 456, width: 789, height: 321)
        XCTAssertEqual(resolver.inferState(from: odd, on: screen), .floating)
    }

    func testInferStateReturnsFloatingForZeroRect() {
        XCTAssertEqual(resolver.inferState(from: .zero, on: screen), .floating)
    }

    // MARK: LayoutResolver — interpolation

    func testInterpolateAtZeroReturnsFrom() {
        let from = CGRect(x: 0, y: 0, width: 100, height: 100)
        let to   = CGRect(x: 500, y: 500, width: 200, height: 200)
        XCTAssertEqual(resolver.interpolate(from: from, to: to, progress: 0), from)
    }

    func testInterpolateAtOneReturnsTo() {
        let from = CGRect(x: 0, y: 0, width: 100, height: 100)
        let to   = CGRect(x: 500, y: 500, width: 200, height: 200)
        XCTAssertEqual(resolver.interpolate(from: from, to: to, progress: 1), to)
    }

    func testInterpolateAtMidpointIsHalfway() {
        let from = CGRect(x: 0, y: 0, width: 100, height: 100)
        let to   = CGRect(x: 200, y: 200, width: 300, height: 300)
        let mid  = resolver.interpolate(from: from, to: to, progress: 0.5)
        XCTAssertEqual(mid.origin.x, 100, accuracy: 0.001)
        XCTAssertEqual(mid.origin.y, 100, accuracy: 0.001)
        XCTAssertEqual(mid.width,    200, accuracy: 0.001)
        XCTAssertEqual(mid.height,   200, accuracy: 0.001)
    }

    func testInterpolateClampsBelowZero() {
        let from = CGRect(x: 0, y: 0, width: 100, height: 100)
        let to   = CGRect(x: 100, y: 100, width: 200, height: 200)
        XCTAssertEqual(resolver.interpolate(from: from, to: to, progress: -1), from)
    }

    func testInterpolateClampsBeyondOne() {
        let from = CGRect(x: 0, y: 0, width: 100, height: 100)
        let to   = CGRect(x: 100, y: 100, width: 200, height: 200)
        XCTAssertEqual(resolver.interpolate(from: from, to: to, progress: 2), to)
    }
}

// MARK: - WindowRecord history

final class WindowRecordTests: XCTestCase {

    func testInitialStateIsAccessible() {
        let record = WindowRecord(currentState: .floating)
        XCTAssertEqual(record.currentState, .floating)
        XCTAssertNil(record.previousState)
    }

    func testTransitionUpdatesBothCurrentAndPrevious() {
        var record = WindowRecord(currentState: .floating)
        record.transition(to: .leftHalf)
        XCTAssertEqual(record.currentState,  .leftHalf)
        XCTAssertEqual(record.previousState, .floating)
    }

    func testRewindRestoresPreviousState() {
        var record = WindowRecord(currentState: .floating)
        record.transition(to: .leftHalf)
        record.transition(to: .leftThird)
        let landed = record.rewind()
        XCTAssertEqual(landed,               .leftHalf)
        XCTAssertEqual(record.currentState,  .leftHalf)
    }

    func testRewindOnEmptyHistoryReturnsNil() {
        var record = WindowRecord(currentState: .center)
        let result = record.rewind()
        XCTAssertNil(result)
        XCTAssertEqual(record.currentState, .center)
    }

    func testHistoryIsCappedAtTwelveEntries() {
        var record = WindowRecord(currentState: .floating)
        let cycle: [WindowLayoutState] = [.leftHalf, .center, .rightHalf, .fullscreen]
        for i in 0..<15 {
            record.transition(to: cycle[i % cycle.count])
        }
        // Rewind 12 times to drain the capped history — must not crash
        for _ in 0..<12 {
            record.rewind()
        }
        // One more rewind on empty history must return nil
        XCTAssertNil(record.rewind())
    }

    func testFloatingFrameIsPreserved() {
        let savedFrame = CGRect(x: 100, y: 200, width: 800, height: 600)
        var record = WindowRecord(currentState: .floating, floatingFrame: savedFrame)
        XCTAssertEqual(record.floatingFrame, savedFrame)
        record.transition(to: .leftHalf)
        XCTAssertEqual(record.floatingFrame, savedFrame, "floatingFrame must survive transitions")
    }

    func testMultipleTransitionsTrackFullHistory() {
        var record = WindowRecord(currentState: .floating)
        let states: [WindowLayoutState] = [.leftHalf, .leftThird, .leftBottomSixth, .rightBottomSixth]
        for s in states { record.transition(to: s) }

        // Unwind all the way back
        var seen: [WindowLayoutState] = []
        while let s = record.rewind() { seen.append(s) }

        XCTAssertEqual(seen.first, states[states.count - 2]) // second-to-last state
        XCTAssertEqual(seen.last,  .floating)
    }
}
