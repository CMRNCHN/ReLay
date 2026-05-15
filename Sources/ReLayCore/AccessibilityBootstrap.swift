import ApplicationServices
import Foundation

public enum AccessibilityBootstrap {
    public static func ensurePermission(promptIfNeeded: Bool = true) -> Bool {
        let processName = ProcessInfo.processInfo.processName
        let processIdentifier = ProcessInfo.processInfo.processIdentifier
        let executablePath = CommandLine.arguments.first ?? "unknown"

        AppLogger.log(
            "checking accessibility trust process=\(processName) pid=\(processIdentifier) path=\(executablePath)",
            subsystem: "accessibility"
        )

        let trusted = AXIsProcessTrusted()
        AppLogger.log(
            trusted ? "accessibility permission granted" : "accessibility permission missing",
            subsystem: "accessibility"
        )

        guard !trusted, promptIfNeeded else {
            return trusted
        }

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let promptedTrusted = AXIsProcessTrustedWithOptions(options)

        if promptedTrusted {
            AppLogger.log("accessibility permission granted after prompt check", subsystem: "accessibility")
        } else {
            AppLogger.log("requested accessibility permission prompt", subsystem: "accessibility")
        }

        return promptedTrusted
    }
}
