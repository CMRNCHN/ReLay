import AppKit
import ApplicationServices
import XCTest
@testable import ReLayCore

/// Read-only probe of the real desktop. Nothing is moved.
///   RELAY_LIVE_SMOKE=1 swift test --filter LiveWindowProbeTests
///
/// Writes a dump to storage/diagnostics/live-window-probe.txt so the companion
/// heuristic can be judged against the user's actual window set.
final class LiveWindowProbeTests: XCTestCase {

    private func requireLive() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["RELAY_LIVE_SMOKE"] != "1",
                      "Set RELAY_LIVE_SMOKE=1 to run the live probe")
        try XCTSkipUnless(AXIsProcessTrusted(), "Accessibility not granted to the test runner")
    }

    func testDumpVisibleWindowsAndCompanionPick() throws {
        try requireLive()

        var report: [String] = []
        func log(_ line: String) { report.append(line); print(line) }

        let screen = Self.usableScreen(containing: NSScreen.main?.frame ?? .zero)
        log("usable screen (AX coords): \(screen)")

        let windows = AXWindowOps.allVisible()
        log("AXWindowOps.allVisible() → \(windows.count) windows")

        let order = WindowServerList.onScreenOrder()
        var candidates: [CompanionSelector.Candidate] = []
        for (i, win) in windows.enumerated() {
            let bundle = AXWindowOps.bundleID(for: win)
            guard let frame = AXWindowOps.frame(win) else {
                log(String(format: "%3d  %-45@  <no frame>", i, bundle as NSString))
                continue
            }
            let overlap = frame.intersection(screen)
            let onScreen = !overlap.isNull && overlap.width > 0 && overlap.height > 0
            log(String(format: "%3d  %-45@ %@  area=%9.0f  onScreen=%@  role=%@/%@  close=%@  title=%@",
                       i, bundle as NSString, "\(frame)" as NSString,
                       frame.width * frame.height,
                       (onScreen ? "yes" : "NO ") as NSString,
                       Self.attribute(win, kAXRoleAttribute) as NSString,
                       Self.attribute(win, kAXSubroleAttribute) as NSString,
                       (Self.hasAttribute(win, kAXCloseButtonAttribute) ? "yes" : "NO ") as NSString,
                       AXWindowOps.title(win) as NSString))
            var pid: pid_t = 0
            AXUIElementGetPid(win, &pid)
            guard let z = WindowServerList.zOrder(of: frame, pid: pid, in: order) else {
                log("     ↳ not reported by the window server — another Space, skipped")
                continue
            }
            candidates.append(.init(id: i, frame: frame, bundleID: bundle, zOrder: z))
        }

        let own = Bundle.main.bundleIdentifier.map { Set([$0]) } ?? []
        log("")
        log("=== WindowEligibility (tile vs ignore) ===")
        for (i, win) in windows.enumerated() {
            let bundle = AXWindowOps.bundleID(for: win)
            guard let frame = AXWindowOps.frame(win) else { continue }
            var pid: pid_t = 0
            AXUIElementGetPid(win, &pid)
            let regular = WindowEligibility.isRegularApp(pid: pid)
            let substantial = WindowEligibility.isSubstantialFrame(frame, on: screen)
            let tileable = WindowEligibility.isTileableWindow(win, on: screen)
            let resizable = AXWindowOps.isResizable(win).map { $0 ? "yes" : "NO " } ?? "??? "
            let verdict = tileable ? "TILE" : "IGNORE"
            log(String(format: "%3d  %-6@  regular=%@  substantial=%@  resizable=%@  %@  %@",
                       i,
                       verdict as NSString,
                       (regular ? "yes" : "NO ") as NSString,
                       (substantial ? "yes" : "NO ") as NSString,
                       resizable as NSString,
                       bundle as NSString,
                       AXWindowOps.title(win) as NSString))
        }

        log("")
        log("CG layer-0 entries that pass / fail CG prefilter:")
        for (i, entry) in order.enumerated() {
            let ok = WindowEligibility.isTileableCGEntry(
                pid: entry.pid, bounds: entry.bounds, on: screen
            )
            let app = NSRunningApplication(processIdentifier: entry.pid)
            let name = app?.localizedName ?? "?"
            let policy = app.map { "\($0.activationPolicy.rawValue)" } ?? "?"
            log(String(format: "  %3d  %-6@  policy=%@  %@  %@",
                       i,
                       (ok ? "TILE" : "IGNORE") as NSString,
                       policy as NSString,
                       name as NSString,
                       "\(entry.bounds)" as NSString))
        }

        log("")
        log("after a leftHalf snap of window[0], bestCompanion would pick:")
        let excludingPrimary = candidates.filter { $0.id != 0 }
        if let pick = CompanionSelector.best(from: excludingPrimary, on: screen, excludingBundleIDs: own) {
            log("  → id=\(pick.id) \(pick.bundleID) \(pick.frame)")
            log("  → it would be moved to \(LayoutFrameResolver.companionFrames(for: .leftHalf, count: 1, in: screen).first.map { "\($0)" } ?? "nothing")")
        } else {
            log("  → nothing")
        }

        // Windows that AX reports but that are not on the active Space are
        // indistinguishable here — they are still eligible companions.
        let offActiveScreen = candidates.filter {
            let o = $0.frame.intersection(screen)
            return o.isNull || o.width <= 0 || o.height <= 0
        }
        log("")
        log("candidates with no intersection with the active screen: \(offActiveScreen.count)")

        // CGWindowList with .optionOnScreenOnly only reports windows on the
        // *current* Space; AX reports every Space. Anything AX sees that the
        // window server does not is a window the user cannot see right now.
        let onCurrentSpace = (CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] ?? []).compactMap { entry -> (pid_t, CGRect)? in
            guard let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                  let b = entry[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = b["X"], let y = b["Y"], let w = b["Width"], let h = b["Height"]
            else { return nil }
            return (pid, CGRect(x: x, y: y, width: w, height: h))
        }
        log("CGWindowList on-screen entries: \(onCurrentSpace.count)")
        for (i, win) in windows.enumerated() {
            var pid: pid_t = 0
            AXUIElementGetPid(win, &pid)
            guard let frame = AXWindowOps.frame(win) else { continue }
            let visible = onCurrentSpace.contains {
                $0.0 == pid && abs($0.1.minX - frame.minX) < 4 && abs($0.1.minY - frame.minY) < 4
            }
            if !visible {
                log("  AX window \(i) (\(AXWindowOps.bundleID(for: win)) \(frame)) is NOT on the current Space")
            }
        }

        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("storage/diagnostics/live-window-probe.txt")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? report.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    /// Reading the window list must not change the system. `allVisible()` used
    /// to switch AXEnhancedUserInterface *on* for every running app, which makes
    /// the window server animate AX frame writes — the size/position/size
    /// sequence in `setFrame` then races its own animation and the window lands
    /// somewhere else.
    func testAllVisibleDoesNotEnableEnhancedUserInterface() throws {
        try requireLive()

        let attribute = AXWindowOps.enhancedUserInterfaceAttribute as CFString
        func read(_ pid: pid_t) -> Bool? {
            var ref: CFTypeRef?
            AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), attribute, &ref)
            return ref as? Bool
        }

        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        try XCTSkipIf(apps.isEmpty, "no regular apps running")
        print("AXEnhancedUserInterface before: " +
              apps.map { "\($0.bundleIdentifier ?? "?")=\(String(describing: read($0.processIdentifier)))" }
                  .joined(separator: " "))

        // Park one app in the state a window manager wants, then read the list.
        let probe = apps[0]
        AXUIElementSetAttributeValue(AXUIElementCreateApplication(probe.processIdentifier),
                                     attribute, false as CFTypeRef)
        XCTAssertNotEqual(read(probe.processIdentifier), true, "probe app should start with the flag off")

        _ = AXWindowOps.allVisible()

        XCTAssertNotEqual(read(probe.processIdentifier), true,
                          "allVisible() re-enabled AXEnhancedUserInterface on \(probe.bundleIdentifier ?? "?")")
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> String {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &ref) == .success,
              let value = ref as? String else { return "—" }
        return value
    }

    private static func hasAttribute(_ element: AXUIElement, _ name: String) -> Bool {
        var ref: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &ref) == .success && ref != nil
    }

    private static func usableScreen(containing frame: CGRect) -> CGRect {
        guard let primary = NSScreen.screens.first else { return .zero }
        let target = NSScreen.main ?? primary
        let vf = target.visibleFrame
        return CGRect(x: vf.minX, y: primary.frame.height - vf.minY - vf.height,
                      width: vf.width, height: vf.height)
    }
}
