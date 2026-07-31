import XCTest
@testable import ReLayCore

final class LinkedResizeTests: XCTestCase {

    private let gap: CGFloat = 8
    private let screen = CGRect(x: 0, y: 0, width: 1200, height: 800)

    func testDetectsRightEdge() {
        let frame = CGRect(x: 100, y: 100, width: 400, height: 300)
        XCTAssertEqual(LinkedResize.edge(at: CGPoint(x: 500, y: 250), of: frame), .right)
        XCTAssertEqual(LinkedResize.edge(at: CGPoint(x: 100, y: 250), of: frame), .left)
        XCTAssertEqual(LinkedResize.edge(at: CGPoint(x: 300, y: 100), of: frame), .top)
        XCTAssertEqual(LinkedResize.edge(at: CGPoint(x: 300, y: 400), of: frame), .bottom)
        XCTAssertNil(LinkedResize.edge(at: CGPoint(x: 300, y: 250), of: frame))
    }

    func testNeighborSharesRightEdgeAcrossGap() {
        let left = CGRect(x: 4, y: 4, width: 592, height: 792)
        let right = CGRect(x: 604, y: 4, width: 592, height: 792) // 8pt gap
        XCTAssertTrue(LinkedResize.shares(.right, of: left, with: right, gap: gap))
        XCTAssertTrue(LinkedResize.shares(.left, of: right, with: left, gap: gap))
        XCTAssertFalse(LinkedResize.shares(.right, of: left, with: CGRect(x: 900, y: 4, width: 200, height: 200), gap: gap))
    }

    func testResizingRightEdgeGrowsNeighborLeftEdge() {
        let left = CGRect(x: 4, y: 4, width: 500, height: 792)
        let right = CGRect(x: 512, y: 4, width: 684, height: 792)
        let leftNow = CGRect(x: 4, y: 4, width: 700, height: 792)

        let next = LinkedResize.resizedNeighbor(right, sharing: .right, primaryNow: leftNow, gap: gap)
        XCTAssertNotNil(next)
        XCTAssertEqual(next!.minX, leftNow.maxX + gap, accuracy: 0.5)
        XCTAssertEqual(next!.maxX, right.maxX, accuracy: 0.5)
        XCTAssertEqual(next!.height, right.height, accuracy: 0.5)
    }

    func testResizingLeftEdgeShrinksNeighbor() {
        let left = CGRect(x: 4, y: 4, width: 500, height: 792)
        let right = CGRect(x: 512, y: 4, width: 684, height: 792)
        let rightNow = CGRect(x: 400, y: 4, width: 796, height: 792)

        let next = LinkedResize.resizedNeighbor(left, sharing: .left, primaryNow: rightNow, gap: gap)!
        XCTAssertEqual(next.maxX, rightNow.minX - gap, accuracy: 0.5)
        XCTAssertEqual(next.minX, left.minX, accuracy: 0.5)
    }

    func testVerticalStackSharesBottomEdge() {
        let top = CGRect(x: 4, y: 4, width: 1192, height: 390)
        let bottom = CGRect(x: 4, y: 402, width: 1192, height: 390)
        XCTAssertTrue(LinkedResize.shares(.bottom, of: top, with: bottom, gap: gap))

        let topNow = CGRect(x: 4, y: 4, width: 1192, height: 500)
        let next = LinkedResize.resizedNeighbor(bottom, sharing: .bottom, primaryNow: topNow, gap: gap)!
        XCTAssertEqual(next.minY, topNow.maxY + gap, accuracy: 0.5)
        XCTAssertEqual(next.maxY, bottom.maxY, accuracy: 0.5)
    }

    func testRefusesToShrinkNeighborBelowMinimum() {
        let left = CGRect(x: 4, y: 4, width: 900, height: 792)
        let right = CGRect(x: 912, y: 4, width: 280, height: 792)
        let leftNow = CGRect(x: 4, y: 4, width: 1050, height: 792) // would leave ~142 for right
        XCTAssertNil(LinkedResize.resizedNeighbor(right, sharing: .right, primaryNow: leftNow, gap: gap, minSize: 180))
    }

    func testHalvesFromResolverAreRecognizedAsNeighbors() {
        let left = LayoutFrameResolver.frame(for: .leftHalf, in: screen, gap: gap)
        let right = LayoutFrameResolver.frame(for: .rightHalf, in: screen, gap: gap)
        XCTAssertTrue(LinkedResize.shares(.right, of: left, with: right, gap: gap))
        let indices = LinkedResize.neighborIndices(of: left, edge: .right, among: [right], gap: gap)
        XCTAssertEqual(indices, [0])
    }

    func testCornerHitPrefersNearerEdge() {
        let frame = CGRect(x: 100, y: 100, width: 400, height: 300)
        // Closer to right than bottom (both within thickness)
        XCTAssertEqual(LinkedResize.edge(at: CGPoint(x: 499, y: 395), of: frame), .right)
        // Closer to bottom than right (both within thickness)
        XCTAssertEqual(LinkedResize.edge(at: CGPoint(x: 495, y: 399), of: frame), .bottom)
    }
}
