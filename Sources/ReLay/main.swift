import Foundation
import AppKit
import ReLayCore

AppLogger.log("bootstrapping runtime", subsystem: "startup")

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let gestureEngine = GestureEngine()
    private let titleBarInterceptor = TitleBarInterceptor()
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLogger.log("application did finish launching", subsystem: "startup")

        _ = SpatialTransitionEngine.shared
        _ = WindowStateStore.shared

        setupMenuBar()
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

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: "ReLay")
        }

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(NSMenuItem(title: "Open Layout Exposé", action: #selector(openExpose), keyEquivalent: " "))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Undo Last Layout", action: #selector(undoLayout), keyEquivalent: "z"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit ReLay", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    @objc private func openExpose() {
        guard let frontmost = getFrontmostWindow() else { return }
        LayoutExposeController.shared.present(triggerWindow: frontmost)
    }

    @objc private func undoLayout() {
        SpatialTransitionEngine.shared.performExposeUndo()
    }

    private func getFrontmostWindow() -> AXUIElement? {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(frontmostApp.processIdentifier)
        var ref: CFTypeRef?
        if AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &ref) == .success {
            return (ref as! AXUIElement)
        }
        if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &ref) == .success,
           let list = ref as? [AXUIElement], !list.isEmpty {
            return list[0]
        }
        return nil
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        menu.item(withTitle: "Undo Last Layout")?.isEnabled = SpatialTransitionEngine.shared.canUndo
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()

app.delegate = delegate
app.setActivationPolicy(.accessory)

AppLogger.log("starting application loop", subsystem: "startup")

app.run()
