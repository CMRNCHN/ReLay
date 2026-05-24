import Foundation
import AppKit
import ReLayCore

AppLogger.log("bootstrapping runtime", subsystem: "startup")
CrashLogger.setup()

// Single instance enforcement
let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.relay.app"
let runningApps = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == bundleIdentifier }
if runningApps.count > 1 {
    AppLogger.log("another instance of ReLay is already running, terminating", subsystem: "startup")
    // Try to activate the other one? No, just quit.
    exit(0)
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let gestureEngine = GestureEngine()
    private let titleBarInterceptor = TitleBarInterceptor()
    private var statusItem: NSStatusItem?
    private var isInterceptionDisabled = false
    private var settingsWindowController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLogger.log("application did finish launching", subsystem: "startup")

        _ = SpatialTransitionEngine.shared
        _ = WindowStateStore.shared

        setupMenuBar()
        titleBarInterceptor.delegate = gestureEngine

        checkAccessibilityAndStart()
        checkConflicts()

        NotificationCenter.default.addObserver(self, selector: #selector(toggleInterception), name: NSNotification.Name("ReLayEmergencyStop"), object: nil)

        AppLogger.log("runtime active", subsystem: "startup")
    }

    private func checkAccessibilityAndStart() {
        let accessibilityReady = AccessibilityBootstrap.ensurePermission(promptIfNeeded: false)

        if accessibilityReady {
            startInterceptor()
        } else {
            showAccessibilityAlert()
        }
    }

    private func startInterceptor() {
        do {
            AppLogger.log("starting title bar interceptor", subsystem: "startup")
            try titleBarInterceptor.start()
            AppLogger.log("title bar interceptor started", subsystem: "startup")
        } catch {
            AppLogger.log("failed to start title bar interceptor: \(error)", subsystem: "startup")
        }
    }

    private func checkConflicts() {
        let conflicts = AccessibilityBootstrap.checkForConflictingApps()
        if !conflicts.isEmpty {
            let alert = NSAlert()
            alert.messageText = "Potential Conflicts Detected"
            alert.informativeText = "ReLay detected other window managers running: \(conflicts.joined(separator: ", ")).\n\nHaving multiple window managers active may lead to unpredictable gesture behavior or shortcut conflicts."
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    private func showAccessibilityAlert() {
        if AXIsProcessTrusted() {
            startInterceptor()
            return
        }

        let alert = NSAlert()
        alert.messageText = "Accessibility Permissions Required"
        alert.informativeText = "ReLay needs Accessibility permissions to intercept title bar gestures and manage your windows.\n\nPlease grant permission in System Settings > Privacy & Security > Accessibility and then click 'Check Again'."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Check Again")
        alert.addButton(withTitle: "Quit")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            NSWorkspace.shared.open(url)
            // Wait for user to interact with Settings then check again manually
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.showAccessibilityAlert()
            }
        } else if response == .alertSecondButtonReturn {
            checkAccessibilityAndStart()
        } else {
            NSApplication.shared.terminate(nil)
        }
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
        menu.addItem(NSMenuItem(title: "Open Layout Exposé", action: #selector(openExpose), keyEquivalent: " "))
        menu.addItem(NSMenuItem(title: "Preferences...", action: #selector(openPreferences), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())

        let killSwitchItem = NSMenuItem(title: "Disable Interception", action: #selector(toggleInterception), keyEquivalent: "k")
        killSwitchItem.keyEquivalentModifierMask = [.command, .shift, .option]
        menu.addItem(killSwitchItem)

        menu.addItem(NSMenuItem(title: "Undo Last Layout", action: #selector(undoLayout), keyEquivalent: "z"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit ReLay", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    @objc private func openExpose() {
        guard let frontmost = getFrontmostWindow() else { return }
        LayoutExposeController.shared.present(triggerWindow: frontmost)
    }

    @objc private func openPreferences() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }
        settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func undoLayout() {
        SpatialTransitionEngine.shared.performExposeUndo()
    }

    @objc private func toggleInterception() {
        isInterceptionDisabled.toggle()
        if isInterceptionDisabled {
            titleBarInterceptor.stop()
            AppLogger.log("interception disabled via kill-switch", subsystem: "startup")
        } else {
            startInterceptor()
            AppLogger.log("interception re-enabled", subsystem: "startup")
        }
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
