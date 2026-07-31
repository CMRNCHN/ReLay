import XCTest
@testable import ReLayCore

final class SeamGeometryTests: XCTestCase {

    private let gap: CGFloat = 8
    private let screen = CGRect(x: 0, y: 0, width: 1200, height: 800)

    func testDetectsVerticalSeamBetweenHalves() {
        let left = LayoutFrameResolver.frame(for: .leftHalf, in: screen, gap: gap)
        let right = LayoutFrameResolver.frame(for: .rightHalf, in: screen, gap: gap)
        let seams = SeamGeometry.seams(among: [left, right], gap: gap)
        XCTAssertEqual(seams.count, 1)
        XCTAssertEqual(seams[0].axis, .vertical)
        XCTAssertEqual(seams[0].firstIndex, 0)
        XCTAssertEqual(seams[0].secondIndex, 1)
        XCTAssertEqual(seams[0].center, (left.maxX + right.minX) / 2, accuracy: 0.5)
    }

    func testHandleRectCenteredOnSeam() {
        let left = LayoutFrameResolver.frame(for: .leftHalf, in: screen, gap: gap)
        let right = LayoutFrameResolver.frame(for: .rightHalf, in: screen, gap: gap)
        let seam = SeamGeometry.seams(among: [left, right], gap: gap)[0]
        let handle = SeamGeometry.handleRect(for: seam)
        XCTAssertEqual(handle.midX, seam.center, accuracy: 0.5)
        XCTAssertGreaterThan(handle.height, 20)
        XCTAssertLessThanOrEqual(handle.width, 8)
    }

    func testDividerDragResizesBothSides() {
        let left = CGRect(x: 4, y: 4, width: 500, height: 792)
        let right = CGRect(x: 512, y: 4, width: 684, height: 792)
        let pair = SeamGeometry.frames(
            first: left, second: right,
            axis: .vertical, dividerCenter: 600, gap: gap
        )
        XCTAssertNotNil(pair)
        XCTAssertEqual(pair!.0.maxX + gap, pair!.1.minX, accuracy: 1)
        XCTAssertEqual(pair!.0.minX, left.minX, accuracy: 0.5)
        XCTAssertEqual(pair!.1.maxX, right.maxX, accuracy: 0.5)
    }

    func testDividerRespectsMinimumSize() {
        let left = CGRect(x: 4, y: 4, width: 500, height: 792)
        let right = CGRect(x: 512, y: 4, width: 684, height: 792)
        XCTAssertNil(SeamGeometry.frames(
            first: left, second: right,
            axis: .vertical, dividerCenter: 1100, gap: gap, minSize: 180
        ))
    }

    func testHorizontalSeamBetweenStackedWindows() {
        let top = CGRect(x: 4, y: 4, width: 1192, height: 390)
        let bottom = CGRect(x: 4, y: 402, width: 1192, height: 390)
        let seams = SeamGeometry.seams(among: [top, bottom], gap: gap)
        XCTAssertEqual(seams.count, 1)
        XCTAssertEqual(seams[0].axis, .horizontal)
    }
}
