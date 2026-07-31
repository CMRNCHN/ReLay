import XCTest
@testable import ReLayCore

/// Which window gets dragged along by a snap.
final class CompanionSelectorTests: XCTestCase {

    private let screen = CGRect(x: 0, y: 38, width: 1512, height: 907)

    private func candidate(_ id: Int, _ frame: CGRect, _ bundle: String = "com.example.app",
                           z: Int = 0) -> CompanionSelector.Candidate {
        CompanionSelector.Candidate(id: id, frame: frame, bundleID: bundle, zOrder: z)
    }

    // MARK: - Basic filtering

    func testSkipsWindowsSmallerThanTheMinimumFootprint() {
        let tiny = candidate(1, CGRect(x: 100, y: 100, width: 110, height: 400))
        XCTAssertNil(CompanionSelector.best(from: [tiny], on: screen))
    }

    func testSkipsWindowsOnAnotherDisplay() {
        let offscreen = candidate(1, CGRect(x: -1600, y: 100, width: 900, height: 700))
        XCTAssertNil(CompanionSelector.best(from: [offscreen], on: screen))
    }

    func testSkipsExcludedBundles() {
        let own = candidate(1, CGRect(x: 0, y: 38, width: 900, height: 700), "com.cameroncohen.relay")
        XCTAssertNil(CompanionSelector.best(from: [own], on: screen,
                                            excludingBundleIDs: ["com.cameroncohen.relay"]))
    }

    // MARK: - Selection quality (hypothesis 2)

    /// The user snaps their editor left and expects the window they were just
    /// looking at to fill the right side — not whichever window happens to be
    /// biggest.
    func testPicksFrontmostWindowNotTheLargest() {
        let browser = candidate(1, CGRect(x: 0, y: 38, width: 1512, height: 907), "com.google.Chrome", z: 5)
        let terminal = candidate(2, CGRect(x: 760, y: 400, width: 700, height: 500), "com.apple.Terminal", z: 1)
        XCTAssertEqual(CompanionSelector.best(from: [browser, terminal], on: screen)?.id, 2)
    }

    /// A big window buried behind everything else is not what the user meant.
    func testPrefersFrontWindowOverBuriedOne() {
        let buried = candidate(1, CGRect(x: 0, y: 38, width: 1500, height: 900), "com.apple.mail", z: 9)
        let front = candidate(2, CGRect(x: 100, y: 100, width: 600, height: 500), "com.apple.Terminal", z: 0)
        XCTAssertEqual(CompanionSelector.best(from: [buried, front], on: screen)?.id, 2)
    }

    /// Selection must not depend on the order `AXWindowOps.allVisible()`
    /// happens to return, which follows `NSWorkspace.runningApplications`.
    func testSelectionIsIndependentOfInputOrder() {
        let a = candidate(1, CGRect(x: 0, y: 38, width: 700, height: 700), "com.apple.Terminal", z: 3)
        let b = candidate(2, CGRect(x: 700, y: 38, width: 700, height: 700), "com.apple.mail", z: 2)
        XCTAssertEqual(CompanionSelector.best(from: [a, b], on: screen)?.id, 2)
        XCTAssertEqual(CompanionSelector.best(from: [b, a], on: screen)?.id, 2)
    }

    func testPicksNothingWhenNoCandidateQualifies() {
        XCTAssertNil(CompanionSelector.best(from: [], on: screen))
    }

    // MARK: - Interaction with the snap that triggered it

    /// After snapping the primary to the left half, the companion is moved to
    /// the right half. If the companion was already correctly placed the move
    /// is a no-op; if it was the user's fullscreen browser, a window they never
    /// touched gets resized.
    func testCompanionMoveIsUnconditional() {
        let browser = candidate(1, CGRect(x: 0, y: 38, width: 1512, height: 907), "com.google.Chrome")
        let pick = CompanionSelector.best(from: [browser], on: screen)
        XCTAssertNotNil(pick, "any large window is fair game, however unrelated to the gesture")
    }

    /// Two windows of the same app are independent candidates, so snapping one
    /// Cursor window can re-tile another Cursor window.
    func testSameAppSecondWindowIsEligible() {
        let sibling = candidate(1, CGRect(x: 200, y: 100, width: 900, height: 700), "com.todesktop.230313mzl4w4u92")
        XCTAssertEqual(CompanionSelector.best(from: [sibling], on: screen)?.id, 1)
    }
}
