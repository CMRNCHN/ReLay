import CoreGraphics

/// Semantic action emitted by the input pipeline and consumed by ActionDispatcher.
public enum AppIntent {
    /// Standard in-app navigation (browser, document viewers, etc.)
    case navigateBack
    case navigateForward

    /// In-app zoom — sends Cmd+/Cmd-
    case zoomIn
    case zoomOut

    /// Translate the entire captured workspace by a screen-space delta.
    /// Driven by continuous gesture input; may fire many times per gesture.
    case moveWorkspace(delta: CGPoint)

    /// Capture and persist the current window layout.
    case captureWorkspace(name: String)

    /// Restore a previously captured workspace by its stored ID.
    case restoreWorkspace(id: String)
}
