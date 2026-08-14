import XCTest
import ApplicationServices
@testable import ReLayCore

final class LayoutAssignmentTests: XCTestCase {

    func testAutoFillPrefersRolesThenFillsLeftovers() {
        let template = LayoutTemplate.all.first { $0.id == "coding" }!
        let windows: [LayoutWindowItem] = [
            mockItem(id: "1", app: "iTerm", title: "Terminal", role: .terminal, bundleID: "com.googlecode.iterm2"),
            mockItem(id: "2", app: "Xcode", title: "Code", role: .editor, bundleID: "com.apple.dt.Xcode"),
            mockItem(id: "3", app: "Safari", title: "Docs", role: .browser, bundleID: "com.apple.Safari")
        ]

        let assignments = LayoutAssignment.autoFill(template: template, windows: windows)

        XCTAssertEqual(assignments[0], "com.apple.dt.Xcode", "Main slot should prefer editor")
        XCTAssertEqual(assignments[1], "com.apple.Safari", "Top-right prefers browser")
        XCTAssertEqual(assignments[2], "com.googlecode.iterm2", "Bottom-right prefers terminal")
    }

    func testAutoFillSplitUsesWindowOrderWhenNoRoles() {
        let template = LayoutTemplate.all.first { $0.id == "split" }!
        let windows: [LayoutWindowItem] = [
            mockItem(id: "a", app: "A", title: "A", role: .other, bundleID: "app.a"),
            mockItem(id: "b", app: "B", title: "B", role: .other, bundleID: "app.b"),
            mockItem(id: "c", app: "C", title: "C", role: .other, bundleID: "app.c")
        ]

        let assignments = LayoutAssignment.autoFill(template: template, windows: windows)

        XCTAssertEqual(assignments[0], "app.a")
        XCTAssertEqual(assignments[1], "app.b")
        XCTAssertNil(assignments[2])
    }

    func testAutoFillSkipsWindowsWithoutBundleID() {
        let template = LayoutTemplate.all.first { $0.id == "split" }!
        let windows: [LayoutWindowItem] = [
            mockItem(id: "1", app: "NoID", title: "X", role: .other, bundleID: nil),
            mockItem(id: "2", app: "HasID", title: "Y", role: .other, bundleID: "app.has")
        ]

        let assignments = LayoutAssignment.autoFill(template: template, windows: windows)
        XCTAssertEqual(assignments[0], "app.has")
        XCTAssertNil(assignments[1])
    }

    func testFrameForSlotMapsNormalizedRect() {
        let slot = LayoutTemplate.Slot(id: 0, rect: CGRect(x: 0.0, y: 0.0, width: 0.5, height: 1.0))
        let screen = CGRect(x: 100, y: 50, width: 1000, height: 800)
        let frame = LayoutAssignment.frameForSlot(slot, in: screen)

        XCTAssertEqual(frame.origin.x, 100, accuracy: 0.001)
        XCTAssertEqual(frame.origin.y, 50, accuracy: 0.001)
        XCTAssertEqual(frame.width, 500, accuracy: 0.001)
        XCTAssertEqual(frame.height, 800, accuracy: 0.001)
    }

    func testOrderForQuickApplyPutsTriggerFirst() {
        let a = AXUIElementCreateApplication(getpid())
        let b = AXUIElementCreateSystemWide()
        let ordered = LayoutAssignment.orderForQuickApply(windows: [a, b], trigger: b)
        XCTAssertTrue(CFEqual(ordered[0], b))
        XCTAssertTrue(CFEqual(ordered[1], a))
    }

    private func mockItem(
        id: String,
        app: String,
        title: String,
        role: WindowRole,
        bundleID: String? = nil
    ) -> LayoutWindowItem {
        LayoutWindowItem(
            id: id,
            element: AXUIElementCreateApplication(getpid()),
            title: title,
            appName: app,
            bundleID: bundleID,
            appIcon: nil,
            role: role
        )
    }
}
