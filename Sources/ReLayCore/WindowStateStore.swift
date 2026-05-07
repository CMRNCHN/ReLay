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
class WindowStateStore {
    static let shared = WindowStateStore()
    private var records: [WindowID: WindowRecord] = [:]
    private init() {}

    func record(for window: AXUIElement) -> WindowRecord? {
        return records[WindowID(element: window)]
    }

    func setRecord(_ record: WindowRecord, for window: AXUIElement) {
        records[WindowID(element: window)] = record
    }

    func updateState(_ state: WindowLayoutState, for window: AXUIElement) {
        if var record = records[WindowID(element: window)] {
            record.transition(to: state)
            records[WindowID(element: window)] = record
        }
    }

    func removeRecord(for window: AXUIElement) {
        records.removeValue(forKey: WindowID(element: window))
    }

    func currentState(for window: AXUIElement) -> WindowLayoutState? {
        return records[WindowID(element: window)]?.currentState
    }
}
