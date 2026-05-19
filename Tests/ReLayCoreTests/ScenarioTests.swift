import XCTest
@testable import ReLayCore

final class ScenarioTests: XCTestCase {
    
    func testStateTransitions() {
        let graph = LayoutTransitionGraph()
        
        // Test: Floating -> Right Half
        XCTAssertEqual(graph.nextState(from: .floating, moving: .right), .rightHalf)
        
        // Test: Right Half -> Center (Pull back)
        XCTAssertEqual(graph.nextState(from: .rightHalf, moving: .left), .center)
        
        // Test: Right Half -> Right Third (Push further)
        XCTAssertEqual(graph.nextState(from: .rightHalf, moving: .right), .rightThird)
        
        // Test: Center -> Left Half
        XCTAssertEqual(graph.nextState(from: .center, moving: .left), .leftHalf)

        // Test: Left Half -> Left Third (Push further)
        XCTAssertEqual(graph.nextState(from: .leftHalf, moving: .left), .leftThird)

        // Test: Center -> Fullscreen
        XCTAssertEqual(graph.nextState(from: .center, moving: .up), .fullscreen)
    }
    
    func testDirectionInference() {
        XCTAssertEqual(GestureDirection(effectiveX: 100, effectiveY: 0), .right)
        XCTAssertEqual(GestureDirection(effectiveX: -100, effectiveY: 0), .left)
        XCTAssertEqual(GestureDirection(effectiveX: 0, effectiveY: 100), .up)
        XCTAssertEqual(GestureDirection(effectiveX: 0, effectiveY: -100), .down)
        
        // Dominant axis
        XCTAssertEqual(GestureDirection(effectiveX: 100, effectiveY: 20), .right)
        XCTAssertEqual(GestureDirection(effectiveX: 20, effectiveY: 100), .up)
    }
}
