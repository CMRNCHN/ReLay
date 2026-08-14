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

    func testGrid2x2VerticalSeamMovesAllFour() {
        let frames = AutoLayoutEngine.frames(for: 4, in: screen, gap: gap)!
        // TL, TR, BL, BR — vertical center seam between left and right columns.
        let startCenter = (frames[0].maxX + frames[1].minX) / 2
        let moved = SeamGeometry.applySeamLine(
            frames: frames,
            axis: .vertical,
            startCenter: startCenter,
            newCenter: startCenter + 80,
            gap: gap,
            minSize: 280
        )
        XCTAssertNotNil(moved)
        // Left column (TL, BL) share a new right edge; right column (TR, BR) a new left.
        XCTAssertEqual(moved![0].maxX, moved![2].maxX, accuracy: 0.5)
        XCTAssertEqual(moved![1].minX, moved![3].minX, accuracy: 0.5)
        XCTAssertEqual(moved![0].maxX + gap, moved![1].minX, accuracy: 1)
        // Heights unchanged; widths shifted.
        XCTAssertEqual(moved![0].height, frames[0].height, accuracy: 0.5)
        XCTAssertGreaterThan(moved![0].width, frames[0].width)
        XCTAssertLessThan(moved![1].width, frames[1].width)
    }

    func testGrid2x2HorizontalSeamMovesAllFour() {
        let frames = AutoLayoutEngine.frames(for: 4, in: screen, gap: gap)!
        let startCenter = (frames[0].maxY + frames[2].minY) / 2
        let moved = SeamGeometry.applySeamLine(
            frames: frames,
            axis: .horizontal,
            startCenter: startCenter,
            newCenter: startCenter + 60,
            gap: gap,
            minSize: 280
        )
        XCTAssertNotNil(moved)
        XCTAssertEqual(moved![0].maxY, moved![1].maxY, accuracy: 0.5)
        XCTAssertEqual(moved![2].minY, moved![3].minY, accuracy: 0.5)
        XCTAssertEqual(moved![0].maxY + gap, moved![2].minY, accuracy: 1)
    }

    func testThirdsMiddleSeamOnlyTouchesAdjacentColumns() {
        let frames = AutoLayoutEngine.frames(for: 3, in: screen, gap: gap)!
        let startCenter = (frames[0].maxX + frames[1].minX) / 2
        let moved = SeamGeometry.applySeamLine(
            frames: frames,
            axis: .vertical,
            startCenter: startCenter,
            newCenter: startCenter + 40,
            gap: gap,
            minSize: 280
        )!
        // Rightmost third keeps its far edge.
        XCTAssertEqual(moved[2].maxX, frames[2].maxX, accuracy: 0.5)
        XCTAssertEqual(moved[0].maxX + gap, moved[1].minX, accuracy: 1)
    }

    func testSeamCenterFromPrimaryEdge() {
        let left = CGRect(x: 4, y: 4, width: 500, height: 792)
        XCTAssertEqual(
            SeamGeometry.center(fromPrimary: left, edge: .right, gap: gap),
            left.maxX + gap / 2,
            accuracy: 0.01
        )
    }
}
