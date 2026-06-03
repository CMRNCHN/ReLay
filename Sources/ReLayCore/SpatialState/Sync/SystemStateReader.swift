import AppKit
import CoreGraphics

/// Reads actual window state from the system using CGWindowList exclusively.
/// No AX calls here — this path must be fast enough for periodic reconciliation.
public final class SystemStateReader {

    private let snapshotter = WindowSnapshotter()

    public init() {}

    public func readSystemState() -> [WindowModel] {
        snapshotter.capture()
    }
}
