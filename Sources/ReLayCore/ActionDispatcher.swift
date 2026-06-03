import AppKit
import CoreGraphics

/// Routes AppIntents to the appropriate subsystem — either the WindowEngine
/// (workspace-level operations) or synthetic key events (in-app actions).
///
/// This is the integration seam between the gesture pipeline and execution.
/// The existing gesture → SpatialTransitionEngine path is unchanged; this
/// dispatcher handles intents that originate from higher-level sources
/// (keyboard shortcuts, Shortcuts.app, programmatic calls).
public final class ActionDispatcher {

    public static let shared = ActionDispatcher()

    private let windowEngine = WindowEngine.shared

    private init() {}

    // MARK: - Dispatch

    public func dispatch(_ intent: AppIntent) {
        guard WindowEngine.isAccessibilityGranted else {
            AppLogger.log("ActionDispatcher: accessibility not granted, dropping intent", subsystem: "dispatcher")
            return
        }

        switch intent {

        case .navigateBack:
            sendKey(keyCode: 0x21, modifier: .command)  // Cmd + [

        case .navigateForward:
            sendKey(keyCode: 0x1E, modifier: .command)  // Cmd + ]

        case .zoomIn:
            sendKey(keyCode: 0x18, modifier: .command)  // Cmd + =

        case .zoomOut:
            sendKey(keyCode: 0x1B, modifier: .command)  // Cmd + -

        case .moveWorkspace(let delta):
            windowEngine.moveWorkspace(delta: delta)

        case .captureWorkspace(let name):
            let ws = windowEngine.captureAndSave(name: name)
            AppLogger.log("workspace captured and saved id=\(ws.id)", subsystem: "dispatcher")

        case .restoreWorkspace(let id):
            guard let ws = WorkspaceStore.shared.workspace(id: id) else {
                AppLogger.log("restoreWorkspace: no workspace found for id=\(id)", subsystem: "dispatcher")
                return
            }
            windowEngine.restore(ws)
        }
    }

    // MARK: - Key Synthesis

    private func sendKey(keyCode: CGKeyCode, modifier: CGEventFlags) {
        let src  = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true)
        down?.flags = modifier
        down?.post(tap: .cghidEventTap)

        let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)
        up?.flags = modifier
        up?.post(tap: .cghidEventTap)
    }
}
