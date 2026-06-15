import Foundation

public enum AppLogger {
    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    public static func log(_ message: String, subsystem: String) {
        let timestamp = formatter.string(from: Date())
        let line = "[\(timestamp)] [\(subsystem)] \(message)\n"
        FileHandle.standardOutput.write(Data(line.utf8))
    }

    public static func log(_ message: String, sessionID: String, subsystem: String) {
        let timestamp = formatter.string(from: Date())
        let line = "[\(timestamp)] [\(subsystem)] [sid=\(sessionID)] \(message)\n"
        FileHandle.standardOutput.write(Data(line.utf8))
    }
}
