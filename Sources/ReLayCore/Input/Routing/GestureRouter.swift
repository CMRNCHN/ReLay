import CoreGraphics

// Stateless: pure gesture → intent mapping.
struct GestureRouter: GestureRouting {
    func route(_ gesture: InputGesture) -> AppIntent? {
        switch gesture {
        case .twoFingerSwipeLeft:          return .navigateBack
        case .twoFingerSwipeRight:         return .navigateForward
        case .pinchZoomIn:                 return .zoomIn
        case .pinchZoomOut:                return .zoomOut
        case .threeFingerDrag(let delta):  return .moveWorkspace(delta: delta)
        }
    }
}
