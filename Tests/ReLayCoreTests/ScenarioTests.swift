import XCTest
@testable import ReLayCore

final class ScenarioTests: XCTestCase {

    private let graph = LayoutTransitionGraph()

    // MARK: — horizontal navigation scenarios

    func testFloatingGoesToHalves() {
        XCTAssertEqual(graph.nextState(from: .floating, moving: .left),  .leftHalf)
        XCTAssertEqual(graph.nextState(from: .floating, moving: .right), .rightHalf)
    }

    func testFullscreenGoesToHalves() {
        XCTAssertEqual(graph.nextState(from: .fullscreen, moving: .left),  .leftHalf)
        XCTAssertEqual(graph.nextState(from: .fullscreen, moving: .right), .rightHalf)
    }

    func testCenterGoesToHalves() {
        XCTAssertEqual(graph.nextState(from: .center, moving: .left),  .leftHalf)
        XCTAssertEqual(graph.nextState(from: .center, moving: .right), .rightHalf)
    }

    func testHalvesCrossToOppositeSide() {
        XCTAssertEqual(graph.nextState(from: .leftHalf,  moving: .right), .rightHalf)
        XCTAssertEqual(graph.nextState(from: .rightHalf, moving: .left),  .leftHalf)
    }

    func testHalvesPushToThirds() {
        XCTAssertEqual(graph.nextState(from: .leftHalf,  moving: .left),  .leftThird)
        XCTAssertEqual(graph.nextState(from: .rightHalf, moving: .right), .rightThird)
    }

    func testThirdsPullBackToHalves() {
        XCTAssertEqual(graph.nextState(from: .leftThird,  moving: .right), .leftHalf)
        XCTAssertEqual(graph.nextState(from: .rightThird, moving: .left),  .rightHalf)
    }

    func testThirdsResistOuterEdge() {
        XCTAssertNil(graph.nextState(from: .leftThird,  moving: .left))
        XCTAssertNil(graph.nextState(from: .rightThird, moving: .right))
    }

    func testSixthsCrossColumn() {
        XCTAssertEqual(graph.nextState(from: .leftTopSixth,    moving: .right), .rightTopSixth)
        XCTAssertEqual(graph.nextState(from: .leftBottomSixth, moving: .right), .rightBottomSixth)
        XCTAssertEqual(graph.nextState(from: .rightTopSixth,   moving: .left),  .leftTopSixth)
        XCTAssertEqual(graph.nextState(from: .rightBottomSixth,moving: .left),  .leftBottomSixth)
    }

    func testSixthsResistOuterEdge() {
        XCTAssertNil(graph.nextState(from: .leftTopSixth,     moving: .left))
        XCTAssertNil(graph.nextState(from: .leftBottomSixth,  moving: .left))
        XCTAssertNil(graph.nextState(from: .rightTopSixth,    moving: .right))
        XCTAssertNil(graph.nextState(from: .rightBottomSixth, moving: .right))
    }

    func testFullscreenResistsUp() {
        XCTAssertNil(graph.nextState(from: .fullscreen, moving: .up))
    }

    // MARK: — vertical gestures are direct actions (not graph entries)

    func testAllStatesHaveNoVerticalGraphEntries() {
        for state in WindowLayoutState.allCases {
            XCTAssertNil(graph.nextState(from: state, moving: .up),   "unexpected up entry from \(state)")
            XCTAssertNil(graph.nextState(from: state, moving: .down), "unexpected down entry from \(state)")
        }
    }

    // MARK: — GestureDirection

    func testDirectionInference() {
        XCTAssertEqual(GestureDirection(effectiveX:  100, effectiveY:  0),   .right)
        XCTAssertEqual(GestureDirection(effectiveX: -100, effectiveY:  0),   .left)
        XCTAssertEqual(GestureDirection(effectiveX:  0,   effectiveY:  100), .up)
        XCTAssertEqual(GestureDirection(effectiveX:  0,   effectiveY: -100), .down)
        XCTAssertNil(GestureDirection(effectiveX: 0, effectiveY: 0))
    }

    func testDirectionHorizontalDominates() {
        XCTAssertEqual(GestureDirection(effectiveX:  100, effectiveY:  20), .right)
        XCTAssertEqual(GestureDirection(effectiveX: -100, effectiveY: -20), .left)
    }

    func testDirectionVerticalDominates() {
        XCTAssertEqual(GestureDirection(effectiveX: 20,  effectiveY:  100), .up)
        XCTAssertEqual(GestureDirection(effectiveX: 20,  effectiveY: -100), .down)
    }

    func testDirectionExactTieBreaksToHorizontal() {
        // When |x| == |y|, horizontal wins (abs(x) > abs(y) check is strict)
        XCTAssertEqual(GestureDirection(effectiveX: 50, effectiveY: 50), .up)  // y path
        // (abs(x) is NOT > abs(y) at tie, so vertical branch runs)
    }
}
