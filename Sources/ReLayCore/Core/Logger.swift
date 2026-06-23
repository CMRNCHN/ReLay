import Foundation
import Cocoa

public enum Logger {
    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static var crashLogURL: URL {
        let paths = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
        let libraryDirectory = paths[0].appendingPathComponent("Logs")
        try? FileManager.default.createDirectory(at: libraryDirectory, withIntermediateDirectories: true)
        return libraryDirectory.appendingPathComponent("ReLay-Crash.log")
    }

    public static func log(_ message: String, subsystem: String) {
        let timestamp = formatter.string(from: Date())
        let line = "[\(timestamp)] [\(subsystem)] \(message)\n"
        FileHandle.standardOutput.write(Data(line.utf8))
    }

    public static func setupCrashHandling() {
        checkPreviousCrash()
        NSSetUncaughtExceptionHandler(exceptionHandler)

        signal(SIGABRT, signalHandler)
        signal(SIGILL, signalHandler)
        signal(SIGSEGV, signalHandler)
        signal(SIGFPE, signalHandler)
        signal(SIGBUS, signalHandler)
    }

    private static let exceptionHandler: @convention(c) (NSException) -> Void = { exception in
        Logger.handleException(exception)
    }

    static func handleException(_ exception: NSException) {
        let crashInfo = """
        --- UNCAUGHT EXCEPTION ---
        Date: \(Date())
        Name: \(exception.name.rawValue)
        Reason: \(exception.reason ?? "Unknown")
        Symbols:
        \(exception.callStackSymbols.joined(separator: "\n"))
        --------------------------
        \n
        """
        saveCrash(crashInfo)
    }

    static func handleSignal(_ sig: Int32) {
        let crashInfo = """
        --- SIGNAL RECEIVED (\(sig)) ---
        Date: \(Date())
        Symbols:
        \(Thread.callStackSymbols.joined(separator: "\n"))
        --------------------------
        \n
        """
        saveCrash(crashInfo)
        exit(sig)
    }

    private static func saveCrash(_ info: String) {
        if let data = info.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: crashLogURL.path) {
                if let fileHandle = try? FileHandle(forWritingTo: crashLogURL) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                try? data.write(to: crashLogURL)
            }
        }
        log("Crash detected and saved to \(crashLogURL.path)", subsystem: "safety")
    }

    private static func checkPreviousCrash() {
        guard FileManager.default.fileExists(atPath: crashLogURL.path) else { return }

        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "ReLay quit unexpectedly"
            alert.informativeText = "ReLay detected a previous crash. Would you like to view the crash log?"
            alert.addButton(withTitle: "View Log")
            alert.addButton(withTitle: "Ignore & Delete")

            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(crashLogURL)
            } else {
                try? FileManager.default.removeItem(at: crashLogURL)
            }
        }
    }
}

private func signalHandler(_ sig: Int32) {
    Logger.handleSignal(sig)
}
