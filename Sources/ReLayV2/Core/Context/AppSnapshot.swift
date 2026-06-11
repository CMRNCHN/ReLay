import Foundation
import ApplicationServices

/// A live snapshot of all visible windows at a point in time.
/// `axElement` is a live AX reference valid only during the current session — not persisted.
struct WindowInfo {
    let bundleID: String
    let appName: String
    let windowTitle: String
    let normalizedFrame: NormalizedRect
    let axElement: AXUIElement
}

struct AppSnapshot {
    let timestamp: Date
    let windows: [WindowInfo]
    let screenBounds: CGRect

    var activeApps: [String] {
        Array(Set(windows.map { $0.bundleID }))
    }

    static let empty = AppSnapshot(timestamp: Date(), windows: [], screenBounds: .zero)
}
