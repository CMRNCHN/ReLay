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
        _ = SpatialStateCore.shared

        setupMenuBar()
        titleBarInterceptor.delegate = gestureEngine

        checkAccessibilityAndStart()
        checkConflicts()

        NotificationCenter.default.addObserver(self, selector: #selector(toggleInterception), name: NSNotification.Name("ReLayEmergencyStop"), object: nil)
        NotificationCenter.default.addObserver(forName: NSNotification.Name("ReLayInterceptionToggled"), object: nil, queue: .main) { [weak self] note in
            let enabled = note.userInfo?["enabled"] as? Bool ?? true
            if enabled { self?.startInterceptor() } else { self?.titleBarInterceptor.stop() }
            self?.updateMenuBarIcon(permitted: true)
        }

        AppLogger.log("runtime active", subsystem: "startup")
    }

    private func checkAccessibilityAndStart() {
        if AccessibilityBootstrap.isGranted() {
            startInterceptor()
            updateMenuBarIcon(permitted: true)
        } else {
            showAccessibilityPrompt()
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

    // MARK: - Accessibility permission flow

    private func showAccessibilityPrompt() {
        updateMenuBarIcon(permitted: false)

        // Register silently — makes ReLay appear in System Settings without triggering
        // the macOS system popup (which would cause a confusing double-prompt).
        AccessibilityBootstrap.registerSilently()

        let alert = NSAlert()
        alert.messageText = "Accessibility Access Required"
        alert.informativeText = """
            ReLay needs Accessibility access to intercept title-bar gestures and move windows.

            1. Click "Open Settings" below
            2. Find ReLay in the list and turn it ON
            3. ReLay will start automatically — no need to do anything else
            """
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Quit")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openAccessibilitySettings()
            // Start polling — will auto-start the interceptor the moment permission is granted
            AccessibilityBootstrap.startPolling { [weak self] in
                self?.startInterceptor()
                self?.updateMenuBarIcon(permitted: true)
                self?.showGrantedNotification()
            }
        } else {
            NSApplication.shared.terminate(nil)
        }
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func showGrantedNotification() {
        let alert = NSAlert()
        alert.messageText = "ReLay is Active"
        alert.informativeText = "Accessibility access granted. ReLay is now intercepting title-bar gestures."
        alert.addButton(withTitle: "Got it")
        alert.runModal()
    }

    private func updateMenuBarIcon(permitted: Bool) {
        let symbolName = permitted ? "rectangle.3.group" : "exclamationmark.triangle"
        let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: "ReLay")
        img?.isTemplate = true
        statusItem?.button?.image = img
        statusItem?.button?.toolTip = permitted
            ? "ReLay — active"
            : "ReLay — accessibility access required"
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppLogger.log("application will terminate", subsystem: "startup")
        titleBarInterceptor.stop()
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            let img = NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: "ReLay")
            img?.isTemplate = true
            button.image = img
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open Layout Library", action: #selector(openExpose), keyEquivalent: " "))
        menu.addItem(NSMenuItem(title: "Save Current Layout…", action: #selector(saveCurrentLayout), keyEquivalent: "s"))
        menu.addItem(NSMenuItem(title: "Preferences…", action: #selector(openPreferences), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Undo Last Layout", action: #selector(undoLayout), keyEquivalent: "z"))
        menu.addItem(NSMenuItem(title: "Shuffle Layout Windows", action: #selector(shuffleLayout), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit ReLay", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    @objc private func openExpose() {
        LayoutLibraryController.shared.present(triggerWindow: getFrontmostWindow())
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

    @objc private func shuffleLayout() {
        SpatialTransitionEngine.shared.shuffleExposeLayout()
    }

    @objc private func saveCurrentLayout() {
        LayoutLibraryController.shared.promptSaveCurrentFromMenu()
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
        menu.item(withTitle: "Shuffle Layout Windows")?.isEnabled = SpatialTransitionEngine.shared.canShuffle
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()

app.delegate = delegate
app.setActivationPolicy(.accessory)

AppLogger.log("starting application loop", subsystem: "startup")

app.run()
