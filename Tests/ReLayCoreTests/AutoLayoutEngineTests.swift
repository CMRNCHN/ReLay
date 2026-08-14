import XCTest
@testable import ReLayCore

final class AutoLayoutEngineTests: XCTestCase {

    private let screen = CGRect(x: 0, y: 25, width: 1512, height: 920)
    private let gap: CGFloat = 8

    func testTwoWindowsBecomeHalves() {
        let frames = AutoLayoutEngine.frames(for: 2, in: screen, gap: gap)!
        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(frames[0], LayoutFrameResolver.frame(for: .leftHalf, in: screen, gap: gap))
        XCTAssertEqual(frames[1], LayoutFrameResolver.frame(for: .rightHalf, in: screen, gap: gap))
    }

    func testThreeWindowsBecomeThirds() {
        let frames = AutoLayoutEngine.frames(for: 3, in: screen, gap: gap)!
        XCTAssertEqual(frames.count, 3)
        XCTAssertEqual(frames[0], LayoutFrameResolver.frame(for: .leftThird, in: screen, gap: gap))
        XCTAssertEqual(frames[2], LayoutFrameResolver.frame(for: .rightThird, in: screen, gap: gap))
        // Middle sits flush between left and right with the gap.
        XCTAssertEqual(frames[1].minX, frames[0].maxX + gap, accuracy: 0.5)
        XCTAssertEqual(frames[1].maxX + gap, frames[2].minX, accuracy: 0.5)
    }

    func testFourWindowsBecomeGrid() {
        let frames = AutoLayoutEngine.frames(for: 4, in: screen, gap: gap)!
        XCTAssertEqual(frames.count, 4)
        // Oldest → newest: TL, TR, BL, BR
        XCTAssertEqual(frames[0].minX, frames[2].minX, accuracy: 0.5) // left column
        XCTAssertEqual(frames[1].minX, frames[3].minX, accuracy: 0.5) // right column
        XCTAssertEqual(frames[0].minY, frames[1].minY, accuracy: 0.5) // top row
        XCTAssertEqual(frames[2].minY, frames[3].minY, accuracy: 0.5) // bottom row
        for frame in frames {
            XCTAssertGreaterThanOrEqual(frame.width, AXWindowOps.minWritableWidth)
            XCTAssertGreaterThanOrEqual(frame.height, AXWindowOps.minWritableHeight)
        }
        // Newest (last) is bottom-right.
        XCTAssertGreaterThan(frames[3].minX, frames[0].minX)
        XCTAssertGreaterThan(frames[3].minY, frames[0].minY)
    }

    func testOtherCountsAreIgnored() {
        XCTAssertNil(AutoLayoutEngine.frames(for: 1, in: screen))
        XCTAssertNil(AutoLayoutEngine.frames(for: 5, in: screen))
        XCTAssertNil(AutoLayoutEngine.frames(for: 0, in: screen))
    }

    func testTwoThirdsFramesAreBetweenHalfAndFullscreen() {
        let half = LayoutFrameResolver.frame(for: .leftHalf, in: screen, gap: gap)
        let two = LayoutFrameResolver.frame(for: .leftTwoThirds, in: screen, gap: gap)
        let full = LayoutFrameResolver.frame(for: .fullscreen, in: screen, gap: gap)
        XCTAssertGreaterThan(two.width, half.width)
        XCTAssertLessThan(two.width, full.width)
        XCTAssertEqual(two.minX, half.minX, accuracy: 0.5)
        XCTAssertEqual(two.height, full.height, accuracy: 0.5)
    }

    func testTwoThirdsCompanionIsOppositeThird() {
        let companion = LayoutFrameResolver.companionFrames(for: .leftTwoThirds, count: 1, in: screen, gap: gap)
        XCTAssertEqual(companion.count, 1)
        XCTAssertEqual(companion[0], LayoutFrameResolver.frame(for: .rightThird, in: screen, gap: gap))
    }
}
