import AppKit
import CoreGraphics

/// Thin routing layer: maps AppIntents to the correct subsystem.
/// Contains zero window logic. All spatial mutations go through SpatialStateCore.
/// All layout preset operations go through LayoutManager.
public final class ActionDispatcher {

    public static let shared = ActionDispatcher()

    private let core    = SpatialStateCore.shared
    private let store   = WorkspaceStore.shared
    private let layouts = LayoutManager.shared

    private init() {}

    // MARK: - Dispatch

    public func dispatch(_ intent: AppIntent) {
        guard WindowEngine.isAccessibilityGranted else {
            AppLogger.log("ActionDispatcher: accessibility not granted, dropping intent", subsystem: "dispatcher")
            return
        }

        switch intent {

        case .navigateBack:
            sendKey(keyCode: 0x21, modifier: .command)   // Cmd + [

        case .navigateForward:
            sendKey(keyCode: 0x1E, modifier: .command)   // Cmd + ]

        case .zoomIn:
            sendKey(keyCode: 0x18, modifier: .command)   // Cmd + =

        case .zoomOut:
            sendKey(keyCode: 0x1B, modifier: .command)   // Cmd + -

        case .moveWorkspace(let delta):
            core.applyWorkspaceMove(delta: delta)

        case .captureWorkspace(let name):
            core.captureFromSystem()
            let ws = core.currentState().workspace
            store.save(ws)
            AppLogger.log("workspace captured id=\(ws.id) name=\(name)", subsystem: "dispatcher")

        case .restoreWorkspace(let id):
            guard let ws = store.workspace(id: id) else {
                AppLogger.log("restoreWorkspace: not found id=\(id)", subsystem: "dispatcher")
                return
            }
            WindowEngine.shared.restore(ws)

        case .captureLayout(let name):
            let layout = layouts.capture(name: name)
            AppLogger.log("layout captured '\(name)' id=\(layout.id)", subsystem: "dispatcher")

        case .restoreLayout(let id):
            layouts.restore(id: id)

        case .listLayouts:
            let all = layouts.listLayouts()
            AppLogger.log("layouts: \(all.map { "\($0.name)(\($0.id))" }.joined(separator: ", "))", subsystem: "dispatcher")
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
