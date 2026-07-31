import XCTest
import AppKit
import ApplicationServices
@testable import ReLayCore

/// Live Accessibility smoke — run with:
///   RELAY_LIVE_SMOKE=1 swift test --filter CompanionLayoutLiveTests
final class CompanionLayoutLiveTests: XCTestCase {

    func testApplyCompanionFramesToVisibleWindows() throws {
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

        try XCTSkipIf(windows.count < 2, "Need at least 2 visible windows to smoke-test companions")

        let primary = windows[0]
        guard let start = AXWindowOps.frame(primary) else {
            return XCTFail("primary window has no frame")
        }
        let screen = usableScreen(containing: start)
        XCTAssertFalse(screen.isEmpty)

        let primaryFrame = LayoutFrameResolver.frame(for: .leftHalf, in: screen)
        XCTAssertTrue(AXWindowOps.setFrame(primary, primaryFrame))

        let companions = Array(windows.dropFirst().prefix(4))
        let frames = LayoutFrameResolver.companionFrames(
            for: .leftHalf,
            count: companions.count,
            in: screen
        )
        XCTAssertEqual(frames.count, companions.count)

        for (win, frame) in zip(companions, frames) {
            XCTAssertTrue(AXWindowOps.setFrame(win, frame), "failed to set companion frame")
        }

        // Allow AX to settle, then verify primary landed in the left half region.
        Thread.sleep(forTimeInterval: 0.25)
        guard let after = AXWindowOps.frame(primary) else {
            return XCTFail("primary frame missing after snap")
        }
        XCTAssertEqual(after.minX, primaryFrame.minX, accuracy: 40)
        XCTAssertEqual(after.width, primaryFrame.width, accuracy: 80)

        if let companion = companions.first,
           let companionAfter = AXWindowOps.frame(companion),
           let expected = frames.first {
            XCTAssertEqual(companionAfter.minX, expected.minX, accuracy: 40)
            XCTAssertEqual(companionAfter.width, expected.width, accuracy: 80)
        }
    }

    // Mirror WindowRuntime.usableScreen for the live smoke only.
    private func usableScreen(containing frame: CGRect) -> CGRect {
        guard let primary = NSScreen.screens.first else { return .zero }
        let toAX: (NSScreen) -> CGRect = { s in
            CGRect(
                x: s.frame.minX,
                y: primary.frame.height - s.frame.minY - s.frame.height,
                width: s.frame.width,
                height: s.frame.height
            )
        }
        let target = NSScreen.screens.max(by: {
            toAX($0).intersection(frame).width * toAX($0).intersection(frame).height
                < toAX($1).intersection(frame).width * toAX($1).intersection(frame).height
        }) ?? (NSScreen.main ?? primary)
        let vf = target.visibleFrame
        return CGRect(
            x: vf.minX,
            y: primary.frame.height - vf.minY - vf.height,
            width: vf.width,
            height: vf.height
        )
    }
}
