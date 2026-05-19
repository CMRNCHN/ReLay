import ApplicationServices
import Accessibility
import CoreGraphics

// MARK: - Window Identity

struct WindowID: Hashable {
    let element: AXUIElement
    static func == (lhs: WindowID, rhs: WindowID) -> Bool { CFEqual(lhs.element, rhs.element) }
    func hash(into hasher: inout Hasher) { hasher.combine(CFHash(element)) }
}

// MARK: - Window Record

struct WindowRecord {
    var currentState: WindowLayoutState
    private var history: [WindowLayoutState] = []

    /// The raw frame captured before the window was first managed.
    /// Used to restore the window when transitioning back to .floating.
    var floatingFrame: CGRect?

    init(currentState: WindowLayoutState, floatingFrame: CGRect? = nil) {
        self.currentState = currentState
        self.floatingFrame = floatingFrame
    }

    var previousState: WindowLayoutState? { history.last }

    mutating func transition(to newState: WindowLayoutState) {
        history.append(currentState)
        if history.count > 12 { history.removeFirst() }
        currentState = newState
    }

    /// Undo the most recent transition, returning the state we landed on.
    @discardableResult
    mutating func rewind() -> WindowLayoutState? {
        guard !history.isEmpty else { return nil }
        currentState = history.removeLast()
        return currentState
    }
}

// MARK: - Store

/// Persistent, in-process store of semantic layout state per window.
/// Source of truth for "where is this window in the state graph."
public final class WindowStateStore {
    public static let shared = WindowStateStore()
    private var records: [WindowID: WindowRecord] = [:]
    private init() {
        AppLogger.log("window state store initialized", subsystem: "state")
    }

    func record(for window: AXUIElement) -> WindowRecord? {
        return records[WindowID(element: window)]
    }

    func setRecord(_ record: WindowRecord, for window: AXUIElement, sessionID: String? = nil) {
        let id = WindowID(element: window)
        let previousState = records[id]?.currentState
        records[id] = record

        if let previousState {
            if previousState != record.currentState {
                if let sessionID = sessionID {
                    AppLogger.log("state transition \(previousState) -> \(record.currentState)", sessionID: sessionID, subsystem: "state")
                } else {
                    AppLogger.log("state transition \(previousState) -> \(record.currentState)", subsystem: "state")
                }
            }
        } else {
            if let sessionID = sessionID {
                AppLogger.log("created state record state=\(record.currentState)", sessionID: sessionID, subsystem: "state")
            } else {
                AppLogger.log("created state record state=\(record.currentState)", subsystem: "state")
            }
        }
    }

    func updateState(_ state: WindowLayoutState, for window: AXUIElement, sessionID: String? = nil) {
        if var record = records[WindowID(element: window)] {
            let previousState = record.currentState
            record.transition(to: state)
            records[WindowID(element: window)] = record
            if let sessionID = sessionID {
                AppLogger.log("state transition \(previousState) -> \(state)", sessionID: sessionID, subsystem: "state")
            } else {
                AppLogger.log("state transition \(previousState) -> \(state)", subsystem: "state")
            }
        }
    }

    func removeRecord(for window: AXUIElement) {
        records.removeValue(forKey: WindowID(element: window))
        AppLogger.log("removed state record", subsystem: "state")
    }

    func currentState(for window: AXUIElement) -> WindowLayoutState? {
        return records[WindowID(element: window)]?.currentState
    }
}
