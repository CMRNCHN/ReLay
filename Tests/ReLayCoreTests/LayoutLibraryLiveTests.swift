import XCTest
import AppKit
import ApplicationServices
@testable import ReLayCore

/// Live Accessibility smoke — run with:
///   RELAY_LIVE_SMOKE=1 swift test --filter LayoutLibraryLiveTests
final class LayoutLibraryLiveTests: XCTestCase {

    func testQuickApplySplitMovesVisibleWindows() throws {
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["RELAY_LIVE_SMOKE"] != "1",
            "Set RELAY_LIVE_SMOKE=1 to run live AX smoke"
        )
        try XCTSkipUnless(AXIsProcessTrusted(), "Accessibility not granted for test runner")

        let windows = AXWindowOps.allVisible().filter { win in
            var pid: pid_t = 0
            AXUIElementGetPid(win, &pid)
            guard let app = NSRunningApplication(processIdentifier: pid),
                  app.bundleIdentifier != Bundle.main.bundleIdentifier,
                  app.bundleIdentifier != "com.cameroncohen.relay"
            else { return false }
            return AXWindowOps.frame(win) != nil
        }

        try XCTSkipIf(windows.count < 2, "Need at least 2 visible windows to smoke-test Layout Library")

        let before = windows.compactMap { AXWindowOps.frame($0) }
        XCTAssertEqual(before.count, windows.count)

        LayoutLibrary.shared.quickApply(templateID: "split", triggerWindow: windows[0])

        Thread.sleep(forTimeInterval: 0.25)

        var changed = 0
        for (win, start) in zip(windows, before) {
            guard let after = AXWindowOps.frame(win) else { continue }
            if abs(after.minX - start.minX) > 20
                || abs(after.minY - start.minY) > 20
                || abs(after.width - start.width) > 20
                || abs(after.height - start.height) > 20 {
                changed += 1
            }
        }

        XCTAssertGreaterThanOrEqual(changed, 1, "quickApply should move at least one window")

        // Primary (trigger) should land in left half of its usable screen.
        guard let primaryAfter = AXWindowOps.frame(windows[0]) else {
            return XCTFail("primary frame missing after quickApply")
        }
        let screen = WindowRuntime.usableScreen(containing: primaryAfter)
        let expectedLeft = LayoutAssignment.frameForSlot(
            LayoutTemplate.all.first { $0.id == "split" }!.slots[0],
            in: screen
        )
        XCTAssertEqual(primaryAfter.minX, expectedLeft.minX, accuracy: 40)
        XCTAssertEqual(primaryAfter.width, expectedLeft.width, accuracy: 80)
    }

    func testAutoFillThenApplyPathAgainstLiveWindows() throws {
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["RELAY_LIVE_SMOKE"] != "1",
            "Set RELAY_LIVE_SMOKE=1 to run live AX smoke"
        )
        try XCTSkipUnless(AXIsProcessTrusted(), "Accessibility not granted for test runner")

        let windows = AXWindowOps.allVisible().filter { win in
            var pid: pid_t = 0
            AXUIElementGetPid(win, &pid)
            guard let app = NSRunningApplication(processIdentifier: pid),
                  let bid = app.bundleIdentifier,
                  bid != Bundle.main.bundleIdentifier,
                  bid != "com.cameroncohen.relay",
                  WindowMutabilityPolicy.decision(for: bid) == .allow
            else { return false }
            return AXWindowOps.frame(win) != nil
        }

        try XCTSkipIf(windows.count < 2, "Need at least 2 mutable windows")

        let template = LayoutTemplate.all.first { $0.id == "split" }!
        let items: [LayoutWindowItem] = windows.prefix(4).compactMap { win in
            var pid: pid_t = 0
            AXUIElementGetPid(win, &pid)
            guard let app = NSRunningApplication(processIdentifier: pid) else { return nil }
            let title = AXWindowOps.title(win)
            return LayoutWindowItem(
                id: "\(pid)-\(title)",
                element: win,
                title: title,
                appName: app.localizedName,
                bundleID: app.bundleIdentifier,
                appIcon: nil,
                role: WindowRoleClassifier.classify(appName: app.localizedName, windowTitle: title)
            )
        }

        let assignments = LayoutAssignment.autoFill(template: template, windows: items)
        XCTAssertFalse(assignments.isEmpty, "autoFill should assign at least one slot")

        let screen = WindowRuntime.usableScreen(containing: AXWindowOps.frame(windows[0]) ?? .zero)
        XCTAssertFalse(screen.isEmpty)

        var applied = 0
        for slot in template.slots {
            guard let bid = assignments[slot.id],
                  let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bid })
            else { continue }
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            var ref: CFTypeRef?
            guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &ref) == .success,
                  let list = ref as? [AXUIElement],
                  let win = list.first(where: { AXWindowOps.isStandardWindow($0) })
            else { continue }
            let frame = LayoutAssignment.frameForSlot(slot, in: screen)
            if AXWindowOps.setFrame(win, frame) { applied += 1 }
        }

        XCTAssertGreaterThanOrEqual(applied, 1, "assignment apply path should move windows")
    }
}
