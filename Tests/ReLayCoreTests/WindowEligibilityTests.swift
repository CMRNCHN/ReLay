import XCTest
@testable import ReLayCore

final class WindowEligibilityTests: XCTestCase {

    private let screen = CGRect(x: 0, y: 38, width: 1512, height: 907)

    func testRejectsTinyPalette() {
        let frame = CGRect(x: 100, y: 100, width: 280, height: 400)
        XCTAssertFalse(WindowEligibility.isSubstantialFrame(frame, on: screen))
    }

    func testRejectsMenuBarSizedDropdown() {
        // Typical status-item panel: clears absolute min but not screen fraction.
        let frame = CGRect(x: 1100, y: 40, width: 360, height: 480)
        XCTAssertFalse(WindowEligibility.isSubstantialFrame(frame, on: screen))
    }

    func testAcceptsHalfWindow() {
        let frame = CGRect(x: 4, y: 42, width: 748, height: 899)
        XCTAssertTrue(WindowEligibility.isSubstantialFrame(frame, on: screen))
    }

    func testAcceptsQuarterGridCell() {
        let frame = CGRect(x: 4, y: 42, width: 748, height: 444)
        XCTAssertTrue(WindowEligibility.isSubstantialFrame(frame, on: screen))
    }

    func testAcceptsThirdColumn() {
        let frame = CGRect(x: 4, y: 42, width: 496, height: 899)
        XCTAssertTrue(WindowEligibility.isSubstantialFrame(frame, on: screen))
    }

    func testRejectsOffscreenWindow() {
        let frame = CGRect(x: -1600, y: 100, width: 900, height: 700)
        XCTAssertFalse(WindowEligibility.isSubstantialFrame(frame, on: screen))
    }
}
