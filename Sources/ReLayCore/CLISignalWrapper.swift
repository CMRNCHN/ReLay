import Foundation

public enum CLISignalWrapper {
    private static var signalSource: DispatchSourceSignal?
    private static let serialQueue = DispatchQueue(label: "com.relay.signal-handler")
    private static var shutdownHandlers: [() -> Void] = []
    private static var isShuttingDown = false

    public typealias ShutdownHandler = () -> Void

    public static func setupSignalHandling(onShutdown: @escaping ShutdownHandler) {
        shutdownHandlers.append(onShutdown)
        setupSignalHandlers()
    }

    public static func addShutdownHandler(_ handler: @escaping ShutdownHandler) {
        serialQueue.async {
            shutdownHandlers.append(handler)
        }
    }

    private static func setupSignalHandlers() {
        signal(SIGINT, SIG_DFL)
        signal(SIGTERM, SIG_DFL)

        let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: serialQueue)
        let sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: serialQueue)

        sigintSource.setEventHandler {
            handleShutdownSignal(signal: SIGINT)
        }

        sigtermSource.setEventHandler {
            handleShutdownSignal(signal: SIGTERM)
        }

        sigintSource.resume()
        sigtermSource.resume()

        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)
    }

    private static func handleShutdownSignal(signal: Int32) {
        guard !isShuttingDown else { return }
        isShuttingDown = true

        let signalName = signal == SIGINT ? "SIGINT" : "SIGTERM"
        AppLogger.log("Received \(signalName), initiating graceful shutdown", subsystem: "signal-handler")

        serialQueue.async {
            for handler in shutdownHandlers {
                do {
                    handler()
                } catch {
                    AppLogger.log("Error in shutdown handler: \(error)", subsystem: "signal-handler")
                }
            }

            AppLogger.log("Shutdown handlers completed", subsystem: "signal-handler")
            exit(0)
        }
    }

    public static func shutdown() {
        serialQueue.async {
            guard !isShuttingDown else { return }
            isShuttingDown = true

            AppLogger.log("Initiating programmatic shutdown", subsystem: "signal-handler")

            for handler in shutdownHandlers {
                do {
                    handler()
                } catch {
                    AppLogger.log("Error in shutdown handler: \(error)", subsystem: "signal-handler")
                }
            }

            AppLogger.log("Shutdown handlers completed", subsystem: "signal-handler")
            exit(0)
        }
    }
}
