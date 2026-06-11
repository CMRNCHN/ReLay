import CoreGraphics

enum AppIntent {
    case navigateBack
    case navigateForward
    case zoomIn
    case zoomOut
    case moveWorkspace(delta: CGPoint)
}
