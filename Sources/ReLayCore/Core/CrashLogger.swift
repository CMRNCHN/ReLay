import Foundation
import Cocoa

public enum CrashLogger {
    private static var logURL: URL {
        let paths = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
        let libraryDirectory = paths[0].appendingPathComponent("Logs")
        try? FileManager.default.createDirectory(at: libraryDirectory, withIntermediateDirectories: true)
        return libraryDirectory.appendingPathComponent("ReLay-Crash.log")
    }

    public static func setup() {
        checkPreviousCrash()
        NSSetUncaughtExceptionHandler { exception in
            CrashLogger.handleException(exception)
        }

        signal(SIGABRT) { globalSignalHandler($0) }
        signal(SIGILL)  { globalSignalHandler($0) }
        signal(SIGSEGV) { globalSignalHandler($0) }
        signal(SIGFPE)  { globalSignalHandler($0) }
        signal(SIGBUS)  { globalSignalHandler($0) }
    }

    public static func handleException(_ exception: NSException) {
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

    public static func handleSignal(_ sig: Int32) {
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
            if FileManager.default.fileExists(atPath: logURL.path) {
                if let fileHandle = try? FileHandle(forWritingTo: logURL) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                try? data.write(to: logURL)
            }
        }
        AppLogger.log("Crash detected and saved to \(logURL.path)", subsystem: "safety")
    }

    private static func checkPreviousCrash() {
        guard FileManager.default.fileExists(atPath: logURL.path) else { return }
        
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "ReLay quit unexpectedly"
            alert.informativeText = "ReLay detected a previous crash. Would you like to view the crash log?"
            alert.addButton(withTitle: "View Log")
            alert.addButton(withTitle: "Ignore & Delete")
            
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(logURL)
            } else {
                try? FileManager.default.removeItem(at: logURL)
            }
        }
    }
}

private func globalSignalHandler(_ sig: Int32) {
    CrashLogger.handleSignal(sig)
}
