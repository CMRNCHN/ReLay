import Foundation
import AppKit
import ReLayCore

AppLogger.log("bootstrapping runtime", subsystem: "startup")

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let gestureEngine = GestureEngine()
    private let titleBarInterceptor = TitleBarInterceptor()

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLogger.log("application did finish launching", subsystem: "startup")

        _ = SpatialTransitionEngine.shared
        _ = WindowStateStore.shared

        titleBarInterceptor.delegate = gestureEngine

        let accessibilityReady = AccessibilityBootstrap.ensurePermission()

        if accessibilityReady {
            do {
                AppLogger.log("starting title bar interceptor", subsystem: "startup")
                try titleBarInterceptor.start()
                AppLogger.log("title bar interceptor started", subsystem: "startup")
            } catch {
                AppLogger.log("failed to start title bar interceptor: \(error)", subsystem: "startup")
            }
        } else {
            AppLogger.log("skipping title bar interceptor startup because accessibility trust is unavailable", subsystem: "startup")
            AppLogger.log("continuing without accessibility-dependent hooks", subsystem: "startup")
        }

        AppLogger.log("runtime active", subsystem: "startup")
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppLogger.log("application will terminate", subsystem: "startup")
        titleBarInterceptor.stop()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()

app.delegate = delegate
app.setActivationPolicy(.accessory)

AppLogger.log("starting application loop", subsystem: "startup")

app.run()
