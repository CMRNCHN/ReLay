import ApplicationServices
import Cocoa
import Foundation

public enum AccessibilityBootstrap {

    // MARK: - Permission check

    public static func isGranted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Adds this process to the Accessibility list (triggers the system prompt on first run)
    /// and returns whether permission is already granted.
    @discardableResult
    public static func requestPermission() -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    // MARK: - Polling

    private static var pollingTimer: DispatchSourceTimer?

    /// Starts polling every 0.5 s. Calls `onGranted` on the main queue and stops polling
    /// as soon as `AXIsProcessTrusted()` returns true.
    public static func startPolling(onGranted: @escaping () -> Void) {
        stopPolling()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.5, repeating: 0.5)
        timer.setEventHandler {
            if AXIsProcessTrusted() {
                stopPolling()
                AppLogger.log("accessibility permission granted — starting interceptor", subsystem: "startup")
                onGranted()
            }
        }
        timer.resume()
        pollingTimer = timer
        AppLogger.log("polling for accessibility permission…", subsystem: "startup")
    }

    public static func stopPolling() {
        pollingTimer?.cancel()
        pollingTimer = nil
    }

    // MARK: - Legacy helper (kept for call sites)

    public static func ensurePermission(promptIfNeeded: Bool = true) -> Bool {
        if isGranted() { return true }
        if promptIfNeeded { requestPermission() }
        return isGranted()
    }

    public static func checkForConflictingApps() -> [String] {
        let conflictingBundleIds = [
            "com.knollsoft.Rectangle",
            "com.crowdcafe.window-magnet",
            "com.hegenberg.BetterTouchTool",
            "org.amethyst.Amethyst",
            "com.binaryage.yabai"
        ]
        
        let runningApps = NSWorkspace.shared.runningApplications
        var detected: [String] = []
        
        for app in runningApps {
            if let bundleId = app.bundleIdentifier, conflictingBundleIds.contains(bundleId) {
                detected.append(app.localizedName ?? bundleId)
            }
        }
        
        return detected
    }
}
