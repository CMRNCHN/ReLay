import XCTest
@testable import ReLayCore

final class WindowServerListTests: XCTestCase {

    func testFramesMatchWithinTolerance() {
        let a = CGRect(x: 10, y: 20, width: 300, height: 400)
        let b = CGRect(x: 12, y: 21, width: 301, height: 402)
        XCTAssertTrue(WindowServerList.framesMatch(a, b, tolerance: 4))
        XCTAssertFalse(WindowServerList.framesMatch(a, b, tolerance: 1))
    }

    func testTopmostSkipsTinyOverlaysAndRespectsZOrder() {
        let order = [
            WindowServerList.Entry(pid: 1, bounds: CGRect(x: 0, y: 0, width: 40, height: 40)), // tooltip
            WindowServerList.Entry(pid: 2, bounds: CGRect(x: 0, y: 0, width: 800, height: 600)),
            WindowServerList.Entry(pid: 3, bounds: CGRect(x: 0, y: 0, width: 800, height: 600)),
        ]
        let hit = WindowServerList.topmost(at: CGPoint(x: 100, y: 100), in: order)
        XCTAssertEqual(hit?.pid, 2)
    }

    func testTopmostUsesEdgeSlack() {
        let order = [
            WindowServerList.Entry(pid: 1, bounds: CGRect(x: 100, y: 100, width: 400, height: 300)),
        ]
        // Just outside the right edge, inside slack
        let hit = WindowServerList.topmost(at: CGPoint(x: 504, y: 250), in: order, expandBy: 6)
        XCTAssertEqual(hit?.pid, 1)
        XCTAssertNil(WindowServerList.topmost(at: CGPoint(x: 504, y: 250), in: order, expandBy: 0))
    }

    func testZOrderFindsMatchingEntry() {
        let order = [
            WindowServerList.Entry(pid: 10, bounds: CGRect(x: 0, y: 0, width: 100, height: 100)),
            WindowServerList.Entry(pid: 20, bounds: CGRect(x: 200, y: 200, width: 300, height: 300)),
        ]
        XCTAssertEqual(
            WindowServerList.zOrder(of: CGRect(x: 200, y: 200, width: 300, height: 300), pid: 20, in: order),
            1
        )
        XCTAssertNil(
            WindowServerList.zOrder(of: CGRect(x: 200, y: 200, width: 300, height: 300), pid: 99, in: order)
        )
    }
}
