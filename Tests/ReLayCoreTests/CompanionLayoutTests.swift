import XCTest
@testable import ReLayCore

final class CompanionLayoutTests: XCTestCase {

    private let screen = CGRect(x: 0, y: 0, width: 1200, height: 800)
    private let gap: CGFloat = 8

    func testLeftHalfFillsRightHalf() {
        let frames = LayoutFrameResolver.companionFrames(for: .leftHalf, count: 1, in: screen, gap: gap)
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0], LayoutFrameResolver.frame(for: .rightHalf, in: screen, gap: gap))
    }

    func testRightHalfFillsLeftHalf() {
        let frames = LayoutFrameResolver.companionFrames(for: .rightHalf, count: 1, in: screen, gap: gap)
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0], LayoutFrameResolver.frame(for: .leftHalf, in: screen, gap: gap))
    }

    func testLeftThirdFillsRemainingTwoThirds() {
        let frames = LayoutFrameResolver.companionFrames(for: .leftThird, count: 1, in: screen, gap: gap)
        XCTAssertEqual(frames.count, 1)
        let primary = LayoutFrameResolver.frame(for: .leftThird, in: screen, gap: gap)
        XCTAssertEqual(frames[0].minX, primary.maxX, accuracy: 0.5)
        XCTAssertEqual(frames[0].maxX, LayoutFrameResolver.frame(for: .fullscreen, in: screen, gap: gap).maxX, accuracy: 0.5)
        XCTAssertEqual(frames[0].height, primary.height, accuracy: 0.5)
    }

    func testMultipleCompanionsStackVertically() {
        let frames = LayoutFrameResolver.companionFrames(for: .leftHalf, count: 2, in: screen, gap: gap)
        XCTAssertEqual(frames.count, 2)
        let region = LayoutFrameResolver.frame(for: .rightHalf, in: screen, gap: gap)
        XCTAssertEqual(frames[0].minY, region.minY, accuracy: 0.5)
        XCTAssertEqual(frames[1].maxY, region.maxY, accuracy: 0.5)
        XCTAssertEqual(frames[0].width, region.width, accuracy: 0.5)
        XCTAssertEqual(frames[1].width, region.width, accuracy: 0.5)
        XCTAssertLessThan(frames[0].maxY, frames[1].minY + 0.5)
    }

    func testFullscreenAndCenterLeaveCompanionsAlone() {
        XCTAssertTrue(LayoutFrameResolver.companionFrames(for: .fullscreen, count: 2, in: screen).isEmpty)
        XCTAssertTrue(LayoutFrameResolver.companionFrames(for: .center, count: 2, in: screen).isEmpty)
        XCTAssertTrue(LayoutFrameResolver.companionFrames(for: .floating, count: 2, in: screen).isEmpty)
    }

    func testZeroCountReturnsEmpty() {
        XCTAssertTrue(LayoutFrameResolver.companionFrames(for: .leftHalf, count: 0, in: screen).isEmpty)
    }
}
