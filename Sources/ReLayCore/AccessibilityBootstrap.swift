import ApplicationServices
import Cocoa
import Foundation

public enum AccessibilityBootstrap {
    public static func ensurePermission(promptIfNeeded: Bool = true) -> Bool {
        let trusted = AXIsProcessTrusted()
        if trusted { return true }

        guard promptIfNeeded else { return false }

        let alert = NSAlert()
        alert.messageText = "Accessibility Permissions Required"
        alert.informativeText = "ReLay needs Accessibility permissions to intercept gestures on window title bars and manage window layouts.\n\nPlease click 'Open System Settings' and ensure ReLay is enabled in the Accessibility list."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            // This triggers the system's own dialog if not already present
            let prePromptOptions = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(prePromptOptions)
            
            // Open the specific settings pane
            // macOS 13+ path
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }

        return AXIsProcessTrusted()
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
