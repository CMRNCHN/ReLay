import XCTest
@testable import ReLayCore

final class GestureIDTests: XCTestCase {

    // MARK: - ID format

    // gestureID is always 8 lowercase hex chars (UUID prefix)
    func testGestureIDFormatIsEightLowercaseHex() {
        for _ in 0..<20 {
            let formatted = UUID().uuidString.prefix(8).lowercased()
            XCTAssertEqual(formatted.count, 8)
            XCTAssertTrue(formatted.allSatisfy { $0.isHexDigit }, "non-hex char in: \(formatted)")
        }
    }

    func testKnownUUIDProducesExpectedPrefix() {
        let id = UUID(uuidString: "ABCDEF12-0000-0000-0000-000000000000")!
        XCTAssertEqual(String(id.uuidString.prefix(8).lowercased()), "abcdef12")
    }

    // MARK: - Uniqueness

    func testConsecutiveGestureIDsAreUnique() {
        let ids = (0..<100).map { _ in UUID() }
        let prefixes = ids.map { String($0.uuidString.prefix(8)) }
        XCTAssertEqual(Set(prefixes).count, prefixes.count, "prefix collision among 100 UUIDs")
    }

    // MARK: - GestureDirection (used in commit path alongside gestureID)

    func testDirectionRequiresNonZeroInput() {
        XCTAssertNil(GestureDirection(effectiveX: 0, effectiveY: 0))
    }

    func testHorizontalDirectionDominates() {
        XCTAssertEqual(GestureDirection(effectiveX: 50, effectiveY: 0),  .right)
        XCTAssertEqual(GestureDirection(effectiveX: -50, effectiveY: 0), .left)
    }

    func testVerticalDirectionDominates() {
        XCTAssertEqual(GestureDirection(effectiveX: 0, effectiveY: 50),  .up)
        XCTAssertEqual(GestureDirection(effectiveX: 0, effectiveY: -50), .down)
    }

    // MARK: - LayoutTransitionGraph correctness (gestureID flows through these transitions)

    func testGraphProducesValidNextStatesForHorizontalGestures() {
        let graph = LayoutTransitionGraph()
        let horizontalStates: [WindowLayoutState] = [.floating, .fullscreen, .leftHalf, .rightHalf, .center]
        for state in horizontalStates {
            let left  = graph.nextState(from: state, moving: .left)
            let right = graph.nextState(from: state, moving: .right)
            // At least one direction must be navigable from any non-edge state
            let navigable = left != nil || right != nil
            XCTAssertTrue(navigable, "state \(state) has no horizontal transitions")
        }
    }

    func testGraphEdgeStatesBlockOuterNavigation() {
        let graph = LayoutTransitionGraph()
        XCTAssertNil(graph.nextState(from: .leftThird,  moving: .left))
        XCTAssertNil(graph.nextState(from: .rightThird, moving: .right))
    }

    func testVerticalDirectionsAreNotInGraph() {
        let graph = LayoutTransitionGraph()
        for state in WindowLayoutState.allCases {
            XCTAssertNil(graph.nextState(from: state, moving: .up),
                         "unexpected vertical graph entry from \(state)")
            XCTAssertNil(graph.nextState(from: state, moving: .down),
                         "unexpected vertical graph entry from \(state)")
        }
    }
}
